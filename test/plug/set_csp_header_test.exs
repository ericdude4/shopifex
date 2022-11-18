defmodule Shopifex.Plug.SetCSPHeaderTest do
  use ShopifexWeb.ConnCase, async: true
  alias Shopifex.Plug.SetCSPHeader

  describe "with shop session present in conn" do
    setup [:shop_in_session]

    test "adds myshopify domain and unified admin url to csp header frame ancestors", %{
      conn: conn
    } do
      conn = SetCSPHeader.call(conn, [])

      assert ["frame-ancestors https://admin.shopify.com https://shopifex.myshopify.com;"] =
               Plug.Conn.get_resp_header(conn, "content-security-policy")
    end
  end

  describe "no shop session present in conn" do
    test "throws when shop is not in session", %{conn: conn} do
      assert_raise SetCSPHeader, ~r<Cannot set CSP header>, fn -> SetCSPHeader.call(conn, []) end
    end
  end
end
