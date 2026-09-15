defmodule Shopifex.OAuth do
  @moduledoc """
  Low-level helpers for Shopify's OAuth token endpoint.

  All grants (authorization code, refresh token and token exchange) share the
  same endpoint: `POST https://{shop}/admin/oauth/access_token`. The functions
  in this module return the *normalized* token params which can be persisted
  straight onto the shop record:

      %{
        access_token: "shpat_...",
        scope: "read_products,write_products",
        refresh_token: "shprt_..." | nil,
        access_token_expires_at: %DateTime{} | nil,
        refresh_token_expires_at: %DateTime{} | nil
      }

  When `config :shopifex, expiring_offline_access_tokens: true` is set, the
  authorization code and token exchange grants request an *expiring* offline
  access token. Shopify then returns a 1 hour access token together with a 90
  day refresh token. See
  https://shopify.dev/docs/apps/build/authentication-authorization/access-tokens#offline-access-tokens

  The HTTP client can be swapped (for tests) with
  `config :shopifex, oauth_http_client: MyClient`, where `MyClient`
  implements `Shopifex.OAuth.HTTPClient`.
  """
  require Logger

  @token_exchange_grant "urn:ietf:params:oauth:grant-type:token-exchange"
  @id_token_type "urn:ietf:params:oauth:token-type:id_token"
  @offline_access_token_type "urn:shopify:params:oauth:token-type:offline-access-token"

  @type token_params :: %{
          required(:access_token) => String.t(),
          optional(:scope) => String.t() | nil,
          optional(:refresh_token) => String.t() | nil,
          optional(:access_token_expires_at) => DateTime.t() | nil,
          optional(:refresh_token_expires_at) => DateTime.t() | nil
        }

  @type error ::
          {:error, :invalid_grant, map() | String.t()}
          | {:error, :unexpected_response, map() | String.t()}
          | {:error, :http_error, term()}

  @doc """
  Whether Shopifex should request expiring offline access tokens.

  Controlled by `config :shopifex, expiring_offline_access_tokens: true`.
  Defaults to `false` for backwards compatibility. Public apps must enable this
  before January 1, 2027.
  """
  @spec expiring_offline_access_tokens?() :: boolean()
  def expiring_offline_access_tokens?(),
    do: Application.get_env(:shopifex, :expiring_offline_access_tokens, false) == true

  @doc """
  Whether `Shopifex.Plug.EnsureAccessToken` may obtain an expiring token pair
  for a shop without a valid refresh token by exchanging the merchant's App
  Bridge session token. Defaults to `true`.

  Set `config :shopifex, exchange_tokens_via_session: false` to disable the
  exchange; the plug then only sends the merchant through the OAuth update flow.
  """
  @spec exchange_tokens_via_session?() :: boolean()
  def exchange_tokens_via_session?(),
    do: Application.get_env(:shopifex, :exchange_tokens_via_session, true) != false

  @doc """
  Seconds before the access token expiry at which Shopifex will proactively
  refresh it. Defaults to 300 (5 minutes).

  Controlled by `config :shopifex, access_token_refresh_margin: 300`.
  """
  @spec access_token_refresh_margin() :: non_neg_integer()
  def access_token_refresh_margin(),
    do: Application.get_env(:shopifex, :access_token_refresh_margin, 300)

  @doc """
  Exchanges an OAuth authorization `code` for an access token.

  Used during the install and update flows.
  """
  @spec request_access_token(shop_url :: String.t(), code :: String.t()) ::
          {:ok, token_params()} | error()
  def request_access_token(shop_url, code) do
    %{
      client_id: client_id(),
      client_secret: client_secret(),
      code: code
    }
    |> maybe_put_expiring()
    |> post_token_request(shop_url)
  end

  @doc """
  Refreshes an expiring offline access token using its `refresh_token`.

  Shopify rotates the refresh token on every call; the returned params include
  the *new* refresh token which must replace the stored one. The previous
  refresh token stays usable until the new one is used (or up to 30 days), so a
  lost response can be recovered by retrying with the stored refresh token.

  ## Options

    * `:client_id` / `:client_secret` - override the app credentials, for
      example to refresh a token which belongs to a different Shopify app.
  """
  @spec refresh_access_token(shop_url :: String.t(), refresh_token :: String.t(), Keyword.t()) ::
          {:ok, token_params()} | error()
  def refresh_access_token(shop_url, refresh_token, opts \\ []) do
    %{
      client_id: Keyword.get(opts, :client_id, client_id()),
      client_secret: Keyword.get(opts, :client_secret, client_secret()),
      grant_type: "refresh_token",
      refresh_token: refresh_token
    }
    |> post_token_request(shop_url)
  end

  @doc """
  Exchanges a Shopify session token (ID token issued by App Bridge) for an
  offline access token without redirecting the merchant.

  Fails with `{:error, :invalid_grant, _}` if the session token is expired,
  invalid, or the app is not installed on the shop with the requested scopes.
  """
  @spec exchange_session_token(shop_url :: String.t(), session_token :: String.t()) ::
          {:ok, token_params()} | error()
  def exchange_session_token(shop_url, session_token) do
    %{
      client_id: client_id(),
      client_secret: client_secret(),
      grant_type: @token_exchange_grant,
      subject_token: session_token,
      subject_token_type: @id_token_type,
      requested_token_type: @offline_access_token_type
    }
    |> maybe_put_expiring()
    |> post_token_request(shop_url)
  end

  @doc """
  Cycles a legacy **non-expiring** offline access token into an expiring one
  without merchant involvement, as described in
  https://shopify.dev/docs/apps/build/authentication-authorization/migrate-to-expiring-offline-access-tokens#cycle-existing-tokens-without-waiting-for-a-merchant

  > #### Irreversible and not replayable {: .error}
  >
  > Shopify destroys `non_expiring_access_token` in the same transaction that
  > issues the expiring pair. If the returned params are not persisted, the shop
  > has **no** working token and the merchant must re-authorize the app before
  > it can call the Admin API again. Retrying with the same token fails with
  > `invalid_subject_token`.
  >
  > Shopifex never calls this function on its own. Call it deliberately, one
  > shop at a time, and persist the result (for example with
  > `Shopifex.Shops.update_shop/2` and `Shopifex.Shops.token_params_to_shop_params/1`)
  > inside `Shopifex.Shops.with_access_token_refresh_lock/2` before doing
  > anything else. Skip shops which already hold a refresh token.

  Online, delegate, scope-restricted and already-expiring tokens are rejected by
  Shopify with `{:error, :invalid_grant, %{"error" => "invalid_subject_token"}}`.

  ## Options

    * `:client_id` / `:client_secret` - override the app credentials.
  """
  @spec cycle_offline_access_token(
          shop_url :: String.t(),
          non_expiring_access_token :: String.t(),
          Keyword.t()
        ) :: {:ok, token_params()} | error()
  def cycle_offline_access_token(shop_url, non_expiring_access_token, opts \\ []) do
    %{
      client_id: Keyword.get(opts, :client_id, client_id()),
      client_secret: Keyword.get(opts, :client_secret, client_secret()),
      grant_type: @token_exchange_grant,
      subject_token: non_expiring_access_token,
      subject_token_type: @offline_access_token_type,
      requested_token_type: @offline_access_token_type,
      # Required by Shopify for this grant; the whole point is an expiring token.
      expiring: 1
    }
    |> post_token_request(shop_url)
  end

  @doc """
  Normalizes a decoded token endpoint response body into shop params.

  `expires_in` and `refresh_token_expires_in` are converted into absolute
  `DateTime`s so that they remain meaningful once persisted.
  """
  @spec token_params(body :: map(), now :: DateTime.t()) :: token_params()
  def token_params(body, now \\ DateTime.utc_now()) do
    body = Map.new(body, fn {k, v} -> {to_string(k), v} end)

    %{
      access_token: body["access_token"],
      scope: body["scope"],
      refresh_token: body["refresh_token"],
      access_token_expires_at: expires_at(now, body["expires_in"]),
      refresh_token_expires_at: expires_at(now, body["refresh_token_expires_in"])
    }
  end

  @doc """
  Builds the Shopify OAuth authorize URL which starts the install/update flow.
  """
  @spec authorize_url(shop_url :: String.t(), redirect_uri :: String.t(), Keyword.t()) ::
          String.t()
  def authorize_url(shop_url, redirect_uri, opts \\ []) do
    query =
      [
        client_id: client_id(),
        scope: Keyword.get(opts, :scope, Application.fetch_env!(:shopifex, :scopes)),
        redirect_uri: redirect_uri
      ]
      |> maybe_put_state(Keyword.get(opts, :state))

    "https://#{shop_url}/admin/oauth/authorize?" <> URI.encode_query(query)
  end

  defp maybe_put_state(query, nil), do: query
  defp maybe_put_state(query, ""), do: query
  defp maybe_put_state(query, state), do: query ++ [state: state]

  defp maybe_put_expiring(params) do
    if expiring_offline_access_tokens?() do
      Map.put(params, :expiring, 1)
    else
      params
    end
  end

  defp post_token_request(params, shop_url) do
    url = "https://#{shop_url}/admin/oauth/access_token"

    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    case http_client().post(url, Jason.encode!(params), headers) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"access_token" => access_token} = decoded} when is_binary(access_token) ->
            {:ok, token_params(decoded)}

          _ ->
            {:error, :unexpected_response, body}
        end

      {:ok, %{status_code: status_code, body: body}} when status_code in 400..499 ->
        Logger.warning(
          "Shopify OAuth #{params[:grant_type] || "authorization_code"} grant rejected for #{shop_url} (#{status_code}): #{inspect(body)}"
        )

        {:error, :invalid_grant, decode_error_body(body)}

      {:ok, %{status_code: status_code, body: body}} ->
        Logger.error(
          "Unexpected response from Shopify OAuth endpoint for #{shop_url} (#{status_code}): #{inspect(body)}"
        )

        {:error, :unexpected_response, decode_error_body(body)}

      {:error, reason} ->
        Logger.error("Shopify OAuth request failed for #{shop_url}: #{inspect(reason)}")
        {:error, :http_error, reason}
    end
  end

  defp decode_error_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      _ -> body
    end
  end

  defp decode_error_body(body), do: body

  defp expires_at(_now, nil), do: nil

  defp expires_at(now, seconds) when is_integer(seconds),
    do: now |> DateTime.add(seconds, :second) |> DateTime.truncate(:second)

  defp expires_at(now, seconds) when is_binary(seconds),
    do: expires_at(now, String.to_integer(seconds))

  defp client_id(), do: Application.fetch_env!(:shopifex, :api_key)
  defp client_secret(), do: Application.fetch_env!(:shopifex, :secret)

  defp http_client(),
    do: Application.get_env(:shopifex, :oauth_http_client, Shopifex.OAuth.HTTPClient.HTTPoison)
end
