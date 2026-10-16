defmodule Shopifex.Test do
  @moduledoc """
  Test helpers for apps built on Shopifex.

  Shopifex authenticates requests with signed App Bridge session tokens and
  Shopify HMACs. To test your own controllers and LiveViews behind the
  `:shopify_*` pipelines, you need to *produce* those tokens/HMACs — which means
  re-implementing Shopifex's exact signing rules in your test suite. This module
  does it for you, reusing the same secret/algorithm Shopifex verifies against.

  It ships with the library (it lives in `lib/`, not `test/`), so consuming apps
  can use it directly:

      defmodule MyAppWeb.DashboardLiveTest do
        use MyAppWeb.ConnCase
        import Shopifex.Test

        test "renders for an authenticated shop", %{conn: conn} do
          shop = shop_fixture()

          conn = put_shopify_session(conn, shop)
          # conn now carries a valid Bearer id_token and current_shop is loaded
          # ...
        end
      end

  All functions default the secret/api_key to your `:shopifex` config; pass
  `secret:` / `api_key:` to override (e.g. to test `:old_secret` rotation).
  """

  @doc """
  Signs a valid Shopify App Bridge session token (`id_token`) for `shop_url`.

  ## Options

    * `:secret` / `:api_key` — override the signing secret / audience (default: config)
    * `:expires_in` — seconds until `exp` (default `60`)
    * `:user_id` — the `sub` (merchant user id) claim (default `"1"`)
    * `:claims` — a map merged over the default claims (override `exp`, `dest`, …)
  """
  @spec sign_session_token(String.t(), keyword()) :: String.t()
  def sign_session_token(shop_url, opts \\ []) do
    secret = Keyword.get(opts, :secret) || Application.fetch_env!(:shopifex, :secret)
    api_key = Keyword.get(opts, :api_key) || Application.fetch_env!(:shopifex, :api_key)
    now = System.system_time(:second)

    claims =
      %{
        "dest" => "https://#{shop_url}",
        "iss" => "https://#{shop_url}/admin",
        "aud" => api_key,
        "sub" => to_string(Keyword.get(opts, :user_id, "1")),
        "exp" => now + Keyword.get(opts, :expires_in, 60),
        "nbf" => now - 10,
        "iat" => now
      }
      |> Map.merge(Keyword.get(opts, :claims, %{}))

    jwk = JOSE.JWK.from_oct(secret)
    {_, token} = JOSE.JWT.sign(jwk, %{"alg" => "HS256"}, claims) |> JOSE.JWS.compact()
    token
  end

  @doc """
  Loads `shop` into the conn's Shopifex session and attaches a valid
  `Authorization: Bearer <id_token>` header, so the conn passes the
  `:shopify_session` / `:shopify_api` pipelines and `current_shop/1` resolves.

  Accepts the same options as `sign_session_token/2`, plus `:host` / `:locale`.
  """
  @spec put_shopify_session(Plug.Conn.t(), Shopifex.Plug.shop(), keyword()) :: Plug.Conn.t()
  def put_shopify_session(conn, shop, opts \\ []) do
    token = sign_session_token(Shopifex.Shops.get_url(shop), opts)

    conn
    |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
    |> Shopifex.Plug.build_session(
      shop,
      Keyword.get(opts, :host, "test-host"),
      Keyword.get(opts, :locale, "en")
    )
  end

  @doc """
  Returns the Base64 HMAC for a raw webhook body — the value Shopify sends in the
  `x-shopify-hmac-sha256` header. Pass `secret:` to sign with a non-default key.
  """
  @spec sign_webhook(binary(), keyword()) :: String.t()
  def sign_webhook(raw_body, opts \\ []) do
    secret = Keyword.get(opts, :secret) || Application.fetch_env!(:shopifex, :secret)
    :crypto.mac(:hmac, :sha256, secret, raw_body) |> Base.encode64()
  end

  @doc """
  Prepares a conn to pass the `:shopify_webhook` pipeline: assigns `raw_body` and
  sets a matching `x-shopify-hmac-sha256` header. Identify the shop with the
  `x-shopify-shop-domain` request header (or a `myshopify_domain` in the signed
  body) — `Shopifex.Plug.ShopifyWebhook` resolves the shop from those, not from a
  query/body param a caller could shadow.
  """
  @spec put_webhook_hmac(Plug.Conn.t(), binary(), keyword()) :: Plug.Conn.t()
  def put_webhook_hmac(conn, raw_body, opts \\ []) do
    conn
    |> Plug.Conn.assign(:raw_body, raw_body)
    |> Plug.Conn.put_req_header("x-shopify-hmac-sha256", sign_webhook(raw_body, opts))
  end

  @doc """
  Returns the lowercase-hex HMAC for a query / app-proxy params map — the value
  Shopify sends in the `hmac` (admin load, `&`-joined) or `signature` (app proxy,
  empty joiner) parameter. Params are signed in Shopify's canonical sorted order.

  ## Options

    * `:secret` — signing secret (default: config)
    * `:joiner` — `"&"` for `hmac` (default), `""` for app-proxy `signature`
  """
  @spec sign_query_hmac(map(), keyword()) :: String.t()
  def sign_query_hmac(params, opts \\ []) do
    secret = Keyword.get(opts, :secret) || Application.fetch_env!(:shopifex, :secret)
    joiner = Keyword.get(opts, :joiner, "&")

    # Delegate to the same signer the plugs verify with (incl. the `ids`
    # bulk-action quirk), so forged requests always match — no drift.
    Shopifex.Plug.query_string_hmac(params, joiner, secret)
  end
end
