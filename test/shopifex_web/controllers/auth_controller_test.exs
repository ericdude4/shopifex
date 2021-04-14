defmodule ShopifexWeb.AuthControllerTest do
  use ShopifexWeb.ConnCase, async: true

  test "new shop is redirected to install", %{conn: conn} do
    conn =
      get(conn, Routes.auth_path(@endpoint, :initialize_installation), %{
        "shop" => "shopifex.myshopify.com"
      })

    assert conn.status == 302
    [location] = Plug.Conn.get_resp_header(conn, "location")
    assert location =~ "https://shopifex.myshopify.com/admin/oauth/authorize"
  end

  test "locale is an optional parameter in auth flow", %{conn: conn} do
    query =
      %{
        "shop" => "shopifex.myshopify.com",
        "hmac" => "E0D42CC61A5D3A685D3A7AE652E5BFB0F6D05DDDBE446CA6AC496FFA3FA5488B"
      }
      |> URI.encode_query()

    conn = get(conn, Routes.auth_path(@endpoint, :auth) <> "?#{query}")

    assert conn.status == 302
  end
end
