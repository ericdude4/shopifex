defmodule Shopifex.Plug.ShopifyApiAuth do
  @moduledoc """
  Authenticates async API requests from an embedded SPA front end using the
  Shopify App Bridge session token.

  The front end attaches the token Shopify gives it (via `app-bridge`'s
  `getSessionToken`/`idToken`) as an `Authorization: Bearer <token>` header.
  This plug verifies it with `Shopifex.SessionToken`, resolves the shop, and
  builds the Shopifex session so controllers can call
  `Shopifex.Plug.current_shop/1`.

  On failure it responds `401`, halts, and sets the
  `x-shopify-retry-invalid-session-request: 1` response header. Embedded session
  tokens live only ~60 seconds, so an in-flight or back-forward-cache request
  routinely arrives with an expired token; App Bridge's `authenticatedFetch`
  watches for that header and transparently retries the request with a freshly
  minted `id_token` instead of surfacing the 401 to the user.

  Used by the `:shopify_api` / `:shopifex_api` pipelines. Replaces the
  Guardian-based pipeline used in Shopifex v2.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    with token when is_binary(token) <- Shopifex.Plug.session_token(conn),
         {:ok, %{"dest" => "https://" <> shop_url}} <- Shopifex.SessionToken.verify(token),
         shop when not is_nil(shop) <- Shopifex.Shops.get_shop_by_url(shop_url) do
      Shopifex.Plug.build_session(conn, shop, conn.params["host"], conn.params["locale"] || "en")
    else
      _ ->
        conn
        |> put_resp_header("x-shopify-retry-invalid-session-request", "1")
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "unauthorized", status: 401})
        |> halt()
    end
  end
end
