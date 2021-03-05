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
end
