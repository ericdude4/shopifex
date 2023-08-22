defmodule Shopifex.Plug.ShopifyWebhook do
  @moduledoc """
  Ensures that the connection has a valid Shopify webhook HMAC token and
  builds Shopifex session.
  """
  import Plug.Conn
  require Logger

  def init(options) do
    # initialize options
    options
  end

  def call(conn, _) do
    expected_hmac = Shopifex.Plug.build_hmac(conn)
    received_hmac = Shopifex.Plug.get_hmac(conn)

    if expected_hmac == received_hmac do
      shop =
        conn
        |> get_shop_domain()
        |> Shopifex.Shops.get_shop_by_url()

      if shop do
        host = Map.get(conn.params, "host")
        locale = Map.get(conn.params, "locale")
        Shopifex.Plug.build_session(conn, shop, host, locale)
      else
        # Send 200 response so that Shopify doesn't retry the webhook for a store that doesn't exist.
        conn
        |> send_resp(200, "no store found with url")
        |> halt()
      end
    else
      Logger.info("HMAC doesn't match " <> expected_hmac)

      conn
      |> send_resp(401, "invalid hmac signature")
      |> halt()
    end
  end

  defp get_shop_domain(%Plug.Conn{params: %{"myshopify_domain" => shop_url}}), do: shop_url
  defp get_shop_domain(%Plug.Conn{params: %{"shop" => shop_url}}), do: shop_url

  defp get_shop_domain(%Plug.Conn{} = conn) do
    with [shop_url] <- Plug.Conn.get_req_header(conn, "x-shopify-shop-domain") do
      shop_url
    else
      _ -> nil
    end
  end
end
