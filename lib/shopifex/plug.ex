defmodule Shopifex.Plug do
  @moduledoc """
  An API for accessing the Shopify session data for the current request.
  """
  @type shop :: %{access_token: String.t(), scope: String.t(), url: String.t()}
  @type shopify_host :: String.t()

  @default_timestamp_tolerance_seconds 90

  @doc """
  Get current request shop resource for give `conn`.

  Available in requests that passed through a `:shopify_session`,
  `:managed_install`, or `:shopify_proxy` pipeline. (For `:shopify_proxy`,
  `Shopifex.Plug.LoadProxyShop` resolves it from the signed `shop` param; it is
  `nil` when that shop isn't found.)

  ## Examples:

      iex> current_shop(conn)
      %MyApp.Shop{}

  """
  @spec current_shop(conn :: Plug.Conn.t()) :: shop()
  def current_shop(%Plug.Conn{private: %{shopifex: %{shop: shop}}}), do: shop
  def current_shop(_), do: nil

  @doc """
  Get host parameter provided in URL params when Shopify loaded
  your app in the Shopify admin portal.

  Useful when initializing app-bridge instance from SPA application.

  ## Examples:

      iex> current_shopify_host(conn)
      "host from URL search parameter"

  """
  @spec current_shopify_host(conn :: Plug.Conn.t()) :: shopify_host()
  def current_shopify_host(%Plug.Conn{private: %{shopifex: %{shopify_host: shopify_host}}}),
    do: shopify_host

  def current_shopify_host(_), do: nil

  @doc """
  Returns the Shopify App Bridge session token (`id_token`) for the current
  request, read from the `id_token` or `token` query param, or the
  `Authorization: Bearer` header.

  Embedded apps no longer mint their own session token — Shopify supplies a
  fresh short-lived `id_token` on every embedded page load (App Bridge appends
  it to the URL as `id_token`, and sends it as a `Bearer` token on authenticated
  fetches). Verify it with `Shopifex.SessionToken`.

  ## Example
      iex> session_token(conn)
      "header.payload.signature"
  """
  @spec session_token(conn :: Plug.Conn.t()) :: String.t() | nil
  def session_token(%Plug.Conn{params: %{"id_token" => token}}) when is_binary(token), do: token

  def session_token(%Plug.Conn{params: %{"token" => token}}) when is_binary(token), do: token

  def session_token(%Plug.Conn{} = conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> token
      _ -> nil
    end
  end

  @doc """
  Build the Shopifex session. Used in various `:shopify_*` pipelines.

  Stores the current shop and Shopify host in `conn.private.shopifex`, where
  `current_shop/1` and `current_shopify_host/1` read them, and applies the
  request locale. No app-issued token is minted — embedded auth is carried by
  Shopify's per-request `id_token` (see `Shopifex.SessionToken`).
  """
  @spec build_session(
          conn :: Plug.Conn.t(),
          shop :: shop(),
          shopify_host :: shopify_host(),
          locale :: Gettext.locale()
        ) :: Plug.Conn.t()
  def build_session(conn, shop, host, locale \\ "en") do
    # A non-binary `locale` (e.g. `?locale[]=x`, which parses to a list) would
    # crash `Gettext.put_locale/1`; fall back to the default instead.
    Gettext.put_locale(if is_binary(locale), do: locale, else: "en")

    shopifex_private_data = %{
      shop: shop,
      shopify_host: host
    }

    Plug.Conn.put_private(conn, :shopifex, shopifex_private_data)
  end

  @doc """
  Places given shop into current session, making it accessible later on
  via `Shopifex.Plug.current_shop(conn)`
  """
  @spec put_shop_in_session(conn :: Plug.Conn.t(), shop :: shop()) :: Plug.Conn.t()
  def put_shop_in_session(conn, shop) do
    shopifex_private_data =
      conn.private
      |> Map.get(:shopifex, %{})
      |> Map.put(:shop, shop)

    Plug.Conn.put_private(conn, :shopifex, shopifex_private_data)
  end

  @doc """
  Returns the HMAC the request should carry, computed with the app's current
  secret. Used for verification and for (re)issuing signed values.
  """
  @spec build_hmac(conn :: Plug.Conn.t()) :: String.t()
  def build_hmac(conn), do: build_hmac(conn, primary_secret())

  @doc """
  Like `build_hmac/1`, but computes the HMAC with an explicit `secret`. Used by
  `hmac_matches?/2` to accept either the current or a rotated `:old_secret`.
  """
  @spec build_hmac(conn :: Plug.Conn.t(), secret :: binary()) :: String.t()
  def build_hmac(%Plug.Conn{query_params: %{"hmac" => _}} = conn, secret) do
    # hmac param takes precedence and is present in App load requests.
    conn.query_params
    |> Map.delete("hmac")
    |> query_string_hmac("&", secret)
  end

  def build_hmac(%Plug.Conn{query_params: %{"signature" => _}} = conn, secret) do
    # signature param is present in Shopify App proxy requests https://shopify.dev/apps/online-store/app-proxies
    conn.query_params
    |> Map.delete("signature")
    |> query_string_hmac("", secret)
  end

  def build_hmac(%Plug.Conn{method: "GET"} = conn, secret) do
    conn.query_params
    |> query_string_hmac("", secret)
  end

  def build_hmac(%Plug.Conn{method: "POST"} = conn, secret) do
    # Webhook body HMACs are Base64 and MUST be compared case-sensitively — do
    # not downcase. Shopify (JS/Ruby) compares the raw Base64 digest.
    :crypto.mac(:hmac, :sha256, secret, conn.assigns[:raw_body])
    |> Base.encode64()
  end

  @doc """
  Constant-time check that `received` matches the request's expected HMAC under
  the app's current secret &mdash; or, when `config :shopifex, :old_secret` is
  set, the previous one. Trying both lets you rotate the app secret without
  dropping in-flight webhooks / signed requests still carrying the old signature.
  Returns `false` for a non-binary `received` (e.g. a missing header), and
  `false` without computing anything when a query value is not a string (a
  bracket-syntax `foo[x]=y` parses to a map) — the only non-scalar Shopify
  signs is the bulk-action `ids[]` list.
  """
  @spec hmac_matches?(conn :: Plug.Conn.t(), received :: term()) :: boolean()
  def hmac_matches?(%Plug.Conn{} = conn, received) when is_binary(received) do
    conn = Plug.Conn.fetch_query_params(conn)

    signable_query?(conn.query_params) and
      Enum.any?(secrets(), fn secret ->
        Plug.Crypto.secure_compare(build_hmac(conn, secret), received)
      end)
  end

  def hmac_matches?(_conn, _received), do: false

  # `query_string_hmac/3` interpolates every value and maps over `ids`, so a
  # map value or a scalar `ids` would raise on unauthenticated input. Reject
  # those shapes up front; a genuine Shopify signature never contains them.
  defp signable_query?(query_params) when is_map(query_params) do
    Enum.all?(query_params, fn
      {"ids", ids} -> is_list(ids) and Enum.all?(ids, &is_binary/1)
      {_key, value} -> is_binary(value)
    end)
  end

  @doc """
  Constant-time check that a Shopify **webhook** request is authentic: the
  Base64 `x-shopify-hmac-sha256` header against the HMAC of the raw request
  body (`conn.assigns[:raw_body]`). Tries the rotated `:old_secret` when set.

  Unlike `hmac_matches?/2`, this reads the signature only from the header and
  computes only over the body, so a query-string `hmac`/`signature` a caller
  appended to the URL is never consulted. Returns `false` when the header is
  absent, empty, or the raw body was not captured.
  """
  @spec valid_webhook_hmac?(conn :: Plug.Conn.t()) :: boolean()
  def valid_webhook_hmac?(%Plug.Conn{} = conn) do
    with [received] <- Plug.Conn.get_req_header(conn, "x-shopify-hmac-sha256"),
         true <- is_binary(received) and received != "",
         raw_body when is_binary(raw_body) or is_list(raw_body) <- conn.assigns[:raw_body] do
      Enum.any?(secrets(), fn secret ->
        expected = :crypto.mac(:hmac, :sha256, secret, raw_body) |> Base.encode64()
        Plug.Crypto.secure_compare(expected, received)
      end)
    else
      _ -> false
    end
  end

  @redirect_salt "shopifex signed redirect"
  @redirect_max_age_seconds 90

  @doc """
  Signs an app-issued redirect for `shop_url` that `Shopifex.Plug.ShopifySession`
  will accept **only** at `path` (the request path, without query) and only for
  `:max_age` seconds. Used by `Shopifex.Plug.PaymentGuard` so a request
  authenticated without an App Bridge `id_token` (legacy HMAC / non-embedded)
  still reaches the plans page, and by `ShopifexWeb.PaymentHTML.select_plan_path/1`
  so that page's Select request can authenticate its POST the same way.

  The token is bound to one destination on purpose: it is not a Shopify-style
  query HMAC, so it cannot be replayed on other routes, and a guarded route will
  not mint a fresh one from it.

  ## Options

    * `:max_age` - seconds the token stays valid. Embedded in the token as an
      explicit `exp` claim (and as the `Plug.Crypto` signing max age), so the
      lifetime is fixed at signing time and `verify_redirect/2` needs no
      per-call override. Defaults to #{@redirect_max_age_seconds}.
  """
  @spec sign_redirect(String.t(), String.t(), keyword()) :: String.t()
  def sign_redirect(shop_url, path, opts \\ [])
      when is_binary(shop_url) and is_binary(path) and is_list(opts) do
    max_age = Keyword.get(opts, :max_age, @redirect_max_age_seconds)
    exp = System.system_time(:second) + max_age

    Plug.Crypto.sign(
      primary_secret(),
      @redirect_salt,
      %{shop_url: shop_url, path: path, exp: exp},
      max_age: max_age
    )
  end

  @doc """
  Verifies a token from `sign_redirect/3` against `path`, trying the rotated
  `:old_secret` when set. The lifetime the signer embedded applies: the token
  must be within its `Plug.Crypto` max age **and** its `exp` claim must still
  be in the future. A token without an `exp` claim is rejected. Returns
  `{:ok, shop_url}` or `:error`.
  """
  @spec verify_redirect(term(), String.t()) :: {:ok, String.t()} | :error
  def verify_redirect(token, path) when is_binary(token) and is_binary(path) do
    now = System.system_time(:second)

    Enum.find_value(secrets(), :error, fn secret ->
      case Plug.Crypto.verify(secret, @redirect_salt, token) do
        {:ok, %{shop_url: shop_url, path: ^path, exp: exp}} when is_integer(exp) and exp > now ->
          {:ok, shop_url}

        _ ->
          nil
      end
    end)
  end

  def verify_redirect(_token, _path), do: :error

  @spec get_hmac(conn :: Plug.Conn.t()) :: String.t() | nil
  def get_hmac(%Plug.Conn{params: %{"hmac" => hmac}}) when is_binary(hmac),
    do: String.downcase(hmac)

  def get_hmac(%Plug.Conn{params: %{"signature" => signature}}) when is_binary(signature),
    do: String.downcase(signature)

  def get_hmac(%Plug.Conn{} = conn) do
    # The `x-shopify-hmac-sha256` webhook header is Base64 — return it verbatim
    # for a case-sensitive `secure_compare/2` against the Base64 body digest.
    with [hmac_header] <- Plug.Conn.get_req_header(conn, "x-shopify-hmac-sha256") do
      hmac_header
    else
      _ -> nil
    end
  end

  @doc """
  Validates that the request timestamp in `conn.query_params["timestamp"]` is fresh.

  Options:
    * `:require_timestamp` - boolean, default `false`. When `false`, returns `:ok` if no timestamp is present.
    * `:timestamp_tolerance_seconds` - integer tolerance window in seconds. Defaults to
      `Application.get_env(:shopifex, :hmac_timestamp_tolerance_seconds, 90)`.

  Returns `:ok` or `{:error, reason}` where `reason` is `"missing timestamp"`,
  `"malformed timestamp"` (not a string or integer, e.g. a bracket-syntax
  `timestamp[x]=y` that parses to a map) or `"stale timestamp"`.
  """
  @spec validate_timestamp(conn :: Plug.Conn.t(), opts :: keyword()) :: :ok | {:error, String.t()}
  def validate_timestamp(conn, opts \\ []) do
    # Idempotent: safe even when an earlier plug (or the router) already
    # fetched query params. Without this, a bare `Plug.Test.conn/2` (no
    # `Plug.Parsers`/router in front of it) has `conn.query_params` as
    # `%Plug.Conn.Unfetched{}`, and reading it below would raise.
    conn = Plug.Conn.fetch_query_params(conn)

    case conn.query_params["timestamp"] do
      nil ->
        if Keyword.get(opts, :require_timestamp, false) do
          {:error, "missing timestamp"}
        else
          :ok
        end

      timestamp when is_binary(timestamp) or is_integer(timestamp) ->
        with {seconds, _} <- Integer.parse(to_string(timestamp)),
             true <-
               abs(System.system_time(:second) - seconds) <= timestamp_tolerance_seconds(opts) do
          :ok
        else
          _ -> {:error, "stale timestamp"}
        end

      # `to_string/1` raises on a map (`?timestamp[x]=y`); this check runs
      # before any signature check on unauthenticated input, so it must reject
      # rather than crash.
      _ ->
        {:error, "malformed timestamp"}
    end
  end

  @doc """
  Returns true if the request timestamp is fresh according to `validate_timestamp/2`.
  """
  @spec timestamp_fresh?(conn :: Plug.Conn.t(), opts :: keyword()) :: boolean()
  def timestamp_fresh?(conn, opts \\ []) do
    validate_timestamp(conn, opts) == :ok
  end

  defp timestamp_tolerance_seconds(opts) do
    Keyword.get(opts, :timestamp_tolerance_seconds) ||
      Application.get_env(
        :shopifex,
        :hmac_timestamp_tolerance_seconds,
        @default_timestamp_tolerance_seconds
      )
  end

  @doc false
  # Public only so `Shopifex.Test.sign_query_hmac/2` signs exactly as we verify
  # (incl. the `ids` bulk-action quirk). Not part of the public API.
  def query_string_hmac(query_params, joiner, secret) do
    query_string =
      query_params
      # Shopify signs query/app-proxy params in alphabetical order; sort
      # explicitly rather than relying on map iteration order.
      |> Enum.sort()
      |> Enum.map_join(joiner, fn
        {"ids", value} ->
          # This absolutely ridiculous solution: https://community.shopify.com/c/Shopify-Apps/Hmac-Verification-for-Bulk-Actions/m-p/590611#M18504
          ids =
            Enum.map(value, fn id ->
              "\"#{id}\""
            end)
            |> Enum.join(", ")

          "ids=[#{ids}]"

        {key, value} ->
          "#{key}=#{value}"
      end)

    :crypto.mac(:hmac, :sha256, secret, query_string)
    |> Base.encode16(case: :lower)
  end

  defp primary_secret, do: Application.fetch_env!(:shopifex, :secret)

  # The current secret first, then the rotated-out `:old_secret` if configured,
  # so HMAC verification accepts signatures from before a secret rotation.
  defp secrets do
    case Application.get_env(:shopifex, :old_secret) do
      old when is_binary(old) and old != "" -> [primary_secret(), old]
      _ -> [primary_secret()]
    end
  end
end
