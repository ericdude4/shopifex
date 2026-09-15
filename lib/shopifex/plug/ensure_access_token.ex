defmodule Shopifex.Plug.EnsureAccessToken do
  @moduledoc """
  Ensures that the shop in the session holds a usable *expiring* offline access
  token when `config :shopifex, expiring_offline_access_tokens: true` is set.

  Shops which were installed before expiring tokens were enabled only have a
  non-expiring access token and no refresh token. Shops whose refresh token was
  rejected by Shopify (see `Shopifex.ShopsContext.refresh_access_token/1`) had
  their refresh token cleared. In both cases this plug obtains a fresh token
  pair:

  1. If the request carries a Shopify session token (the `id_token` param which
     App Bridge appends when loading an embedded app, or a session token used as
     the `token` param / bearer token), it is exchanged for an expiring offline
     access token via token exchange. No redirect is required. Disable this
     step with `config :shopifex, upgrade_legacy_tokens_via_session: false`.
  2. Otherwise the merchant is sent through the Shopify OAuth update flow, the
     same way `Shopifex.Plug.EnsureScopes` does for missing scopes.

  This plug never cycles a non-expiring token directly (see
  `Shopifex.OAuth.cycle_offline_access_token/3`); that is an explicit,
  irreversible operation left to the application.

  Shops which already hold a refresh token pass through untouched; refreshing
  the hourly access token itself happens lazily in
  `Shopifex.Shops.get_access_token/1`.

  When expiring tokens are not enabled this plug is a no-op, so it is safe to
  keep in the `:shopify_session` and `:shopify_admin_link` pipelines.
  """
  import Plug.Conn
  import Phoenix.Controller
  require Logger

  def init(options), do: options

  def call(conn, opts \\ []) do
    if Shopifex.OAuth.expiring_offline_access_tokens?() do
      ensure_access_token(conn, opts)
    else
      conn
    end
  end

  defp ensure_access_token(conn, opts) do
    case Shopifex.Plug.current_shop(conn) do
      nil ->
        raise(
          Shopifex.RuntimeError,
          """
          `Shopifex.Plug.EnsureAccessToken` must be placed in the pipeline after a plug which places a shop in the session; such as `Shopifex.Plug.ShopifySession` or `Shopifex.Plug.ShopifyWebhook`
          """
        )

      shop ->
        if Shopifex.Shops.refresh_token_expired?(shop) do
          obtain_expiring_token(conn, shop, opts)
        else
          conn
        end
    end
  end

  defp obtain_expiring_token(conn, shop, opts) do
    shop_url = Shopifex.Shops.get_url(shop)

    Logger.info(
      "Shop #{shop_url} does not hold a valid expiring offline access token, obtaining one"
    )

    with true <- Shopifex.OAuth.upgrade_legacy_tokens_via_session?(),
         {:ok, session_token} <- session_token(conn, shop_url),
         {:ok, token_params} <- Shopifex.OAuth.exchange_session_token(shop_url, session_token) do
      Logger.info("Obtained expiring offline access token for #{shop_url} via token exchange")

      shop =
        Shopifex.Shops.update_shop(
          shop,
          Shopifex.Shops.token_params_to_shop_params(token_params)
        )

      Shopifex.Plug.put_shop_in_session(conn, shop)
    else
      _ ->
        redirect_to_oauth_update(conn, shop_url, opts)
    end
  end

  # Shopify session tokens (ID tokens) are JWTs whose `dest` claim is the shop
  # URL. Shopifex issues its own Guardian tokens with a `sub` claim instead, so
  # only tokens with a matching `dest` claim are candidates for token exchange.
  defp session_token(conn, shop_url) do
    conn
    |> candidate_tokens()
    |> Enum.find(&shopify_session_token?(&1, shop_url))
    |> case do
      nil -> {:error, :no_session_token}
      token -> {:ok, token}
    end
  end

  defp candidate_tokens(conn) do
    bearer =
      case get_req_header(conn, "authorization") do
        ["Bearer " <> token | _] -> token
        _ -> nil
      end

    params =
      case conn.params do
        %Plug.Conn.Unfetched{} -> conn.query_params
        params -> params
      end

    params =
      case params do
        %Plug.Conn.Unfetched{} -> %{}
        params -> params
      end

    [params["id_token"], params["token"], bearer]
    |> Enum.reject(&is_nil/1)
  end

  defp shopify_session_token?(token, shop_url) when is_binary(token) do
    case Shopifex.Guardian.peek(token) do
      %{claims: %{"dest" => "https://" <> ^shop_url}} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp shopify_session_token?(_token, _shop_url), do: false

  defp redirect_to_oauth_update(conn, shop_url, opts) do
    Logger.info(
      "Redirecting #{shop_url} through OAuth to obtain an expiring offline access token"
    )

    reinstall_url =
      Shopifex.OAuth.authorize_url(shop_url, Application.fetch_env!(:shopifex, :reinstall_uri))

    conn
    |> put_view(ShopifexWeb.PageView)
    |> put_layout({ShopifexWeb.LayoutView, "app.html"})
    |> render("redirect.html",
      redirect_location: reinstall_url,
      message: Keyword.get(opts, :message)
    )
    |> halt()
  end
end
