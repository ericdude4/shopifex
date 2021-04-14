defmodule Shopifex.Plug.ShopifyWebhookTest do
  use ShopifexWeb.ConnCase

  setup do
    shop =
      Shopifex.Shops.create_shop(%{
        url: "shopifex.myshopify.com",
        scope: "orders",
        access_token: "asdf1234"
      })

    {:ok, shop: shop}
  end

  test "nil shop with valid HMAC returns 404", %{conn: conn} do
    hmac = "yJgOX9Rf6sY058r98V06ZCrhbw7TlcryRf12e7RmKoU="

    conn =
      conn
      |> Plug.Conn.put_req_header("x-shopify-shop-domain", "noshop.myshopify.com")
      |> Plug.Conn.put_req_header("x-shopify-hmac-sha256", hmac)
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> post(Routes.webhook_path(@endpoint, :action), "{\"foo\": \"bar\"}")

    assert conn.status == 404
  end

  test "valid shop with valid HMAC returns 200", %{conn: conn} do
    hmac = "yJgOX9Rf6sY058r98V06ZCrhbw7TlcryRf12e7RmKoU="

    conn =
      conn
      |> Plug.Conn.put_req_header("x-shopify-shop-domain", "shopifex.myshopify.com")
      |> Plug.Conn.put_req_header("x-shopify-topic", "foo/bar")
      |> Plug.Conn.put_req_header("x-shopify-hmac-sha256", hmac)
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> post(Routes.webhook_path(@endpoint, :action), "{\"foo\": \"bar\"}")

    assert conn.status == 200
  end
end
