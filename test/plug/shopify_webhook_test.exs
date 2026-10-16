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

  test "nil shop with valid HMAC returns 200", %{conn: conn} do
    hmac = "yJgOX9Rf6sY058r98V06ZCrhbw7TlcryRf12e7RmKoU="

    conn =
      conn
      |> Plug.Conn.put_req_header("x-shopify-shop-domain", "noshop.myshopify.com")
      |> Plug.Conn.put_req_header("x-shopify-hmac-sha256", hmac)
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> post("/webhook", "{\"foo\": \"bar\"}")

    assert conn.status == 200
  end

  test "valid shop with invalid HMAC returns 401", %{conn: conn} do
    hmac = "foo"

    conn =
      conn
      |> Plug.Conn.put_req_header("x-shopify-shop-domain", "noshop.myshopify.com")
      |> Plug.Conn.put_req_header("x-shopify-hmac-sha256", hmac)
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> post("/webhook", "{\"foo\": \"bar\"}")

    assert conn.status == 401
  end

  test "valid shop with valid HMAC returns 200", %{conn: conn} do
    hmac = "yJgOX9Rf6sY058r98V06ZCrhbw7TlcryRf12e7RmKoU="

    conn =
      conn
      |> Plug.Conn.put_req_header("x-shopify-shop-domain", "shopifex.myshopify.com")
      |> Plug.Conn.put_req_header("x-shopify-topic", "foo/bar")
      |> Plug.Conn.put_req_header("x-shopify-hmac-sha256", hmac)
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> post("/webhook", "{\"foo\": \"bar\"}")

    assert conn.status == 200
  end

  test "rejects a forged webhook signed only by a query HMAC (no body HMAC header)", %{conn: conn} do
    # Cross-tenant forgery attempt: replay a validly-signed app-load query
    # (attacker's own shop) onto the webhook route, and choose the target shop
    # through the unsigned JSON body. Without a valid x-shopify-hmac-sha256 over
    # the body, the request must be rejected and the victim's row left intact.
    Shopifex.Shops.create_shop(%{url: "victim.myshopify.com", scope: "orders", access_token: "v"})

    signed = %{
      "shop" => "shopifex.myshopify.com",
      "timestamp" => to_string(System.system_time(:second))
    }

    query = URI.encode_query(Map.put(signed, "hmac", Shopifex.Test.sign_query_hmac(signed)))

    conn =
      conn
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Plug.Conn.put_req_header("x-shopify-topic", "shop/redact")
      |> post(
        "/webhook?" <> query,
        Jason.encode!(%{"myshopify_domain" => "victim.myshopify.com"})
      )

    assert conn.status == 401
    assert Shopifex.Shops.get_shop_by_url("victim.myshopify.com")
  end

  describe "admin-link mode" do
    setup do
      Shopifex.Shops.create_shop(%{
        url: "admin.myshopify.com",
        scope: "orders",
        access_token: "t"
      })

      :ok
    end

    defp admin_link_conn(params) do
      signed = Map.put(params, "hmac", Shopifex.Test.sign_query_hmac(params))
      %{Plug.Test.conn(:get, "/") | params: signed, query_params: signed}
    end

    test "a fresh, signed admin link resolves the shop from the signed query" do
      conn =
        %{"shop" => "admin.myshopify.com", "timestamp" => to_string(System.system_time(:second))}
        |> admin_link_conn()
        |> Shopifex.Plug.ShopifyWebhook.call(mode: :admin_link)

      refute conn.halted
      assert Shopifex.Plug.current_shop(conn).url == "admin.myshopify.com"
    end

    test "a stale timestamp is rejected even with a valid signature" do
      conn =
        %{
          "shop" => "admin.myshopify.com",
          "timestamp" => to_string(System.system_time(:second) - 1000)
        }
        |> admin_link_conn()
        |> Shopifex.Plug.ShopifyWebhook.call(mode: :admin_link)

      assert conn.halted
      assert conn.status == 401
    end

    test "an unsigned body shop cannot shadow the signed query shop" do
      Shopifex.Shops.create_shop(%{
        url: "other.myshopify.com",
        scope: "orders",
        access_token: "o"
      })

      signed = %{
        "shop" => "admin.myshopify.com",
        "timestamp" => to_string(System.system_time(:second))
      }

      query_params = Map.put(signed, "hmac", Shopifex.Test.sign_query_hmac(signed))

      conn =
        %{
          Plug.Test.conn(:post, "/")
          | query_params: query_params,
            body_params: %{"shop" => "other.myshopify.com"},
            params: Map.put(query_params, "shop", "other.myshopify.com")
        }
        |> Shopifex.Plug.ShopifyWebhook.call(mode: :admin_link)

      refute conn.halted
      assert Shopifex.Plug.current_shop(conn).url == "admin.myshopify.com"
    end
  end
end
