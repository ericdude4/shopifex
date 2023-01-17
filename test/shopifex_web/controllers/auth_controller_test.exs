defmodule ShopifexWeb.AuthControllerTest do
  use ShopifexWeb.ConnCase, async: true

  test "new shop is redirected to install", %{conn: conn} do
    # Ensure it works with and without trailing slash
    shop_urls = [
      "shopifex.myshopify.com",
      "shopifex.myshopify.com/"
    ]

    for shop_url <- shop_urls do
      conn =
        get(conn, Routes.auth_path(@endpoint, :initialize_installation), %{
          "shop" => shop_url
        })

      assert conn.status == 302
      [location] = Plug.Conn.get_resp_header(conn, "location")
      assert location =~ "https://shopifex.myshopify.com/admin/oauth/authorize"
    end
  end

  test "locale is an optional parameter in auth flow", %{conn: conn} do
    query =
      %{
        "shop" => "shopifex.myshopify.com",
        "hmac" => "E0D42CC61A5D3A685D3A7AE652E5BFB0F6D05DDDBE446CA6AC496FFA3FA5488B"
      }
      |> URI.encode_query()

    conn = get(conn, Routes.auth_path(@endpoint, :auth) <> "?#{query}")

    [location] = Plug.Conn.get_resp_header(conn, "location")

    assert location ==
             "https://shopifex.myshopify.com/admin/oauth/authorize?client_id=thisisafakeapikey&scope=orders&redirect_uri=https://shopifex-dummy.com/auth/install"

    assert conn.status == 302
  end

  test "store selector is rendered with a flash error if an invalid url is passed", %{conn: conn} do
    conn =
      get(conn, Routes.auth_path(@endpoint, :initialize_installation), %{
        "shop" => "invalid.shopify.url"
      })

    body = html_response(conn, 200)
    assert body =~ "Install"
    assert body =~ "Invalid shop URL"
  end
end
