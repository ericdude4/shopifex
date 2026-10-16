defmodule Shopifex.Plug.ShopifySessionTest do
  use ShopifexWeb.ConnCase

  test "responds unauthorized when request content type is json" do
    conn =
      build_conn(:get, "?locale=fr")
      |> Map.merge(%{private: %{phoenix_format: "json"}})
      |> Plug.Conn.fetch_query_params()
      |> Shopifex.Plug.ShopifySession.call([])

    assert %{"message" => "Unauthorized"} = json_response(conn, 403)

    assert conn.halted
  end

  describe "authorized requests" do
    setup [:shop_in_session]

    test "locale is placed in session with locale parameter", %{shop: shop} do
      conn =
        build_conn(:get, "?locale=fr")
        |> Plug.Conn.put_req_header("authorization", "Bearer #{valid_session_token(shop.url)}")
        |> Plug.Conn.fetch_query_params()
        |> Shopifex.Plug.ShopifySession.call([])

      assert %ShopifexDummy.Shop{url: "shopifex.myshopify.com"} = Shopifex.Plug.current_shop(conn)
      assert Gettext.get_locale() == "fr"
    end
  end

  describe "session initialization via query HMAC" do
    test "POST /payment/select-plan does not build session for body shop (cross-tenant param shadowing)",
         %{
           conn: conn
         } do
      shop_a =
        Shopifex.Shops.create_shop(%{
          url: "shop-a.myshopify.com",
          scope: "orders",
          access_token: "tok_a"
        })

      shop_b =
        Shopifex.Shops.create_shop(%{
          url: "shop-b.myshopify.com",
          scope: "orders",
          access_token: "tok_b"
        })

      now = System.system_time(:second)
      query = %{"shop" => shop_a.url, "timestamp" => to_string(now)}
      hmac = Shopifex.Test.sign_query_hmac(query)
      query_string = URI.encode_query(Map.put(query, "hmac", hmac))

      {:ok, plan} =
        Shopifex.Shops.create_plan(%{
          name: "Test Plan",
          price: "10.00",
          features: ["f1"],
          grants: ["g1"],
          type: "recurring_application_charge"
        })

      Req.Test.stub(Shopifex.ReqStub, fn req_conn ->
        Req.Test.json(req_conn, %{
          "data" => %{
            "appSubscriptionCreate" => %{
              "appSubscription" => %{"id" => "gid://shopify/AppSubscription/123"},
              "confirmationUrl" => "https://example.com/confirm",
              "userErrors" => []
            }
          }
        })
      end)

      conn =
        post(conn, "/payment/select-plan?" <> query_string, %{
          "shop" => shop_b.url,
          "plan_id" => to_string(plan.id),
          "redirect_after" => "/after"
        })

      # The signed query names shop_a; the POST body names shop_b. The session
      # must bind to the signed query shop, never the body. Assert
      # unconditionally — a nil shop would be a regression, not a pass.
      loaded_shop = Shopifex.Plug.current_shop(conn)

      assert loaded_shop
      assert loaded_shop.url == shop_a.url
    end

    test "signed GET with timestamp 30 days old is rejected", %{conn: conn} do
      shop =
        Shopifex.Shops.create_shop(%{
          url: "stale-shop.myshopify.com",
          scope: "orders",
          access_token: "tok"
        })

      stale = System.system_time(:second) - 30 * 86_400
      query = %{"shop" => shop.url, "timestamp" => to_string(stale)}
      hmac = Shopifex.Test.sign_query_hmac(query)
      query_string = URI.encode_query(Map.put(query, "hmac", hmac))

      conn = get(conn, "/?" <> query_string)
      assert conn.halted
      assert html_response(conn, 200) =~ "Install Shopifex Dummy"
    end

    test "signed GET with fresh timestamp is accepted", %{conn: conn} do
      shop =
        Shopifex.Shops.create_shop(%{
          url: "fresh-shop.myshopify.com",
          scope: "orders",
          access_token: "tok"
        })

      fresh = System.system_time(:second)
      query = %{"shop" => shop.url, "timestamp" => to_string(fresh)}
      hmac = Shopifex.Test.sign_query_hmac(query)
      query_string = URI.encode_query(Map.put(query, "hmac", hmac))

      conn = get(conn, "/?" <> query_string)
      refute conn.halted
      assert Shopifex.Plug.current_shop(conn).url == shop.url
    end

    test "signed GET without timestamp is accepted", %{conn: conn} do
      shop =
        Shopifex.Shops.create_shop(%{
          url: "notime-shop.myshopify.com",
          scope: "orders",
          access_token: "tok"
        })

      query = %{"shop" => shop.url}
      hmac = Shopifex.Test.sign_query_hmac(query)
      query_string = URI.encode_query(Map.put(query, "hmac", hmac))

      conn = get(conn, "/?" <> query_string)
      refute conn.halted
      assert Shopifex.Plug.current_shop(conn).url == shop.url
    end

    test "handles a bare Plug.Test.conn whose query params were never fetched" do
      shop =
        Shopifex.Shops.create_shop(%{
          url: "unfetched-shop.myshopify.com",
          scope: "orders",
          access_token: "tok"
        })

      query = %{"shop" => shop.url}
      hmac = Shopifex.Test.sign_query_hmac(query)
      query_string = URI.encode_query(Map.put(query, "hmac", hmac))

      # No `fetch_query_params/1` and no router in front — exercises the plug
      # directly the way a consumer's own unit test might.
      conn = Plug.Test.conn(:get, "/?" <> query_string)

      conn = Shopifex.Plug.ShopifySession.call(conn, [])

      refute conn.halted
      assert Shopifex.Plug.current_shop(conn).url == shop.url
    end

    test "signed query without shop param is rejected", %{conn: conn} do
      query = %{"foo" => "bar", "timestamp" => to_string(System.system_time(:second))}
      hmac = Shopifex.Test.sign_query_hmac(query)
      query_string = URI.encode_query(Map.put(query, "hmac", hmac))

      conn = get(conn, "/?" <> query_string)
      assert conn.halted
      assert html_response(conn, 200) =~ "Install Shopifex Dummy"
    end

    test "renders select_store with exactly one doctype even when root layout is configured", %{
      conn: conn
    } do
      defmodule DummyRoot do
        use Phoenix.Component

        def root(assigns) do
          ~H"""
          <!DOCTYPE html>
          <html>
            <body>{@inner_content}</body>
          </html>
          """
        end
      end

      conn =
        conn
        |> init_test_session(%{})
        |> Phoenix.Controller.fetch_flash([])
        |> Phoenix.Controller.put_root_layout(html: {DummyRoot, :root})
        |> Plug.Conn.fetch_query_params()
        |> Shopifex.Plug.ShopifySession.call([])

      assert conn.halted
      body = html_response(conn, 200)
      assert length(Regex.scan(~r/<!DOCTYPE html>/i, body)) == 1
    end
  end
end
