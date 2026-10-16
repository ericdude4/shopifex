defmodule Shopifex.Plug.LoadProxyShop do
  @moduledoc """
  Resolves the shop from a verified Shopify app-proxy request and makes it
  available via `Shopifex.Plug.current_shop/1`.

  App-proxy requests carry a signed `shop` param, but `Shopifex.Plug.ValidateHmac`
  only verifies the signature — it does not load the shop. Run this plug **after**
  `ValidateHmac` (the default `:shopify_proxy` pipeline does) so proxy controllers
  can use `Shopifex.Plug.current_shop(conn)`.

  Shopify signs the app-proxy **query** params only, so this plug reads `shop`
  from `conn.query_params` — the bytes `ValidateHmac` authenticated — not from
  `conn.params`, whose value a `POST` body can shadow.

  ## Options

    * `:on_missing` — what to do when the signed `shop` is absent or not found in
      the database:
      * `:pass` (default) — continue with `current_shop/1` returning `nil`, so
        existing proxy endpoints that don't need the shop are unaffected.
      * `:halt` — respond `401` and halt.

  ## Example

      pipeline :strict_proxy do
        plug :fetch_session
        plug Shopifex.Plug.FetchFlash
        plug Shopifex.Plug.ValidateHmac
        plug Shopifex.Plug.LoadProxyShop, on_missing: :halt
      end
  """
  import Plug.Conn
  require Logger

  def init(options), do: Keyword.put_new(options, :on_missing, :pass)

  def call(conn, options) do
    conn = Plug.Conn.fetch_query_params(conn)

    case conn.query_params do
      %{"shop" => shop_url} when is_binary(shop_url) ->
        load_shop(conn, shop_url, options)

      _ ->
        on_missing(conn, options, "request has no signed shop param")
    end
  end

  defp load_shop(conn, shop_url, options) do
    case Shopifex.Shops.get_shop_by_url(shop_url) do
      nil -> on_missing(conn, options, "no shop found for #{inspect(shop_url)}")
      shop -> Shopifex.Plug.put_shop_in_session(conn, shop)
    end
  end

  defp on_missing(conn, options, reason) do
    case Keyword.fetch!(options, :on_missing) do
      :pass ->
        conn

      :halt ->
        Logger.info("[Shopifex.Plug.LoadProxyShop] rejecting app-proxy request: #{reason}")

        conn
        |> send_resp(401, "Unauthorized")
        |> halt()
    end
  end
end
