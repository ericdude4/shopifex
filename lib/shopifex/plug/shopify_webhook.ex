defmodule Shopifex.Plug.ShopifyWebhook do
  @moduledoc """
  Authenticates a Shopify request and builds the Shopifex session.

  Two modes, chosen with the `:mode` plug option:

    * `:webhook` (default) — a webhook `POST`. The `x-shopify-hmac-sha256`
      header is verified against the HMAC of the **raw request body** (see
      `Shopifex.Plug.valid_webhook_hmac?/1`). The shop is resolved from the
      `x-shopify-shop-domain` header or the verified body — never from a
      query/body param a caller can choose, and a query-string `hmac` is
      ignored.
    * `:admin_link` — an admin-link / bulk-action-link `GET`, signed like an
      app load. The query `hmac` is verified and, when a `timestamp` is
      present, its freshness is checked. The shop is resolved from the signed
      query `shop` param.

  The `:shopify_webhook` and `:shopify_admin_link` pipelines set the mode.
  """
  import Plug.Conn
  require Logger

  def init(options), do: Keyword.put_new(options, :mode, :webhook)

  def call(conn, options) do
    conn = fetch_query_params(conn)

    case Keyword.get(options, :mode, :webhook) do
      :admin_link -> authenticate_admin_link(conn, options)
      _webhook -> authenticate_webhook(conn)
    end
  end

  defp authenticate_webhook(conn) do
    if Shopifex.Plug.valid_webhook_hmac?(conn) do
      build_session_or_halt(conn, webhook_shop_domain(conn))
    else
      reject(conn)
    end
  end

  defp authenticate_admin_link(conn, options) do
    with :ok <- Shopifex.Plug.validate_timestamp(conn, options),
         true <- Shopifex.Plug.hmac_matches?(conn, Shopifex.Plug.get_hmac(conn)) do
      build_session_or_halt(conn, conn.query_params["shop"])
    else
      _ -> reject(conn)
    end
  end

  defp build_session_or_halt(conn, shop_url) do
    case shop_url && Shopifex.Shops.get_shop_by_url(shop_url) do
      shop when not is_nil(shop) ->
        host = Map.get(conn.params, "host")
        locale = Map.get(conn.params, "locale")
        Shopifex.Plug.build_session(conn, shop, host, locale)

      _ ->
        # 200 so Shopify stops retrying a webhook for a store we don't have.
        conn
        |> send_resp(200, "no store found with url")
        |> halt()
    end
  end

  # Prefer Shopify's dedicated header; fall back to the HMAC-verified body.
  # Never the merged `conn.params`, whose value a caller can shadow from the
  # request body.
  defp webhook_shop_domain(conn) do
    case get_req_header(conn, "x-shopify-shop-domain") do
      [shop_url] when is_binary(shop_url) ->
        shop_url

      _ ->
        case conn.body_params do
          %{"myshopify_domain" => shop_url} when is_binary(shop_url) -> shop_url
          %{"shop" => shop_url} when is_binary(shop_url) -> shop_url
          _ -> nil
        end
    end
  end

  defp reject(conn) do
    Logger.info("Rejecting webhook with invalid HMAC")

    conn
    |> send_resp(401, "invalid hmac signature")
    |> halt()
  end
end
