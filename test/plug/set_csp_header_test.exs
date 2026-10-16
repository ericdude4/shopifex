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

    test "preserves existing CSP headers alongside frame-ancestors", %{conn: conn} do
      conn =
        conn
        |> Plug.Conn.put_resp_header("content-security-policy", "script-src 'self'")
        |> SetCSPHeader.call([])

      headers = Plug.Conn.get_resp_header(conn, "content-security-policy")
      assert "script-src 'self'" in headers
      assert Enum.any?(headers, &String.starts_with?(&1, "frame-ancestors"))
    end
  end

  describe "no shop session present in conn" do
    test "throws when shop is not in session", %{conn: conn} do
      assert_raise SetCSPHeader, ~r<Cannot set CSP header>, fn -> SetCSPHeader.call(conn, []) end
    end
  end

  describe "malformed shop url" do
    test "drops a tampered host instead of injecting it into the header", %{conn: conn} do
      # A stored URL carrying a CSP-significant character must not be able to
      # terminate the directive early or add its own. The unified admin origin
      # is always present; the bad host is simply omitted.
      shop =
        Shopifex.Shops.create_shop(%{
          url: "evil.example.com; default-src *",
          scope: "orders",
          access_token: "asdf1234"
        })

      conn =
        conn
        |> Shopifex.Plug.put_shop_in_session(shop)
        |> SetCSPHeader.call([])

      [csp] = Plug.Conn.get_resp_header(conn, "content-security-policy")

      assert csp == "frame-ancestors https://admin.shopify.com;"
      refute csp =~ "default-src"
    end
  end
end
