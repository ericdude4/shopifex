defmodule Shopifex.Plug.LoadInIframeTest do
  use ShopifexWeb.ConnCase, async: true
  alias Shopifex.Plug.LoadInIframe

  defp csp_headers(conn), do: Plug.Conn.get_resp_header(conn, "content-security-policy")

  describe "after Phoenix's put_secure_browser_headers" do
    test "removes both framing restrictions and keeps the other directives", %{conn: conn} do
      conn =
        conn
        |> Phoenix.Controller.put_secure_browser_headers([])
        |> LoadInIframe.call([])

      assert Plug.Conn.get_resp_header(conn, "x-frame-options") == []
      assert csp_headers(conn) == ["base-uri 'self';"]
    end
  end

  test "drops frame-ancestors from every CSP header, matching the name case-insensitively",
       %{conn: conn} do
    conn =
      conn
      |> Plug.Conn.prepend_resp_headers([
        {"content-security-policy", "default-src 'self'; Frame-Ancestors 'none'"},
        {"content-security-policy", "script-src 'self';frame-ancestors 'self';"}
      ])
      |> LoadInIframe.call([])

    assert Enum.sort(csp_headers(conn)) == ["default-src 'self';", "script-src 'self';"]
  end

  test "removes a CSP header that only restricted framing", %{conn: conn} do
    conn =
      conn
      |> Plug.Conn.put_resp_header("content-security-policy", "frame-ancestors 'self';")
      |> LoadInIframe.call([])

    assert csp_headers(conn) == []
  end

  test "leaves a response without CSP headers alone", %{conn: conn} do
    assert csp_headers(LoadInIframe.call(conn, [])) == []
  end

  describe "embedded route" do
    test "only the Shopify admin frame-ancestors policy reaches the browser", %{conn: conn} do
      shop =
        Shopifex.Shops.create_shop(%{
          url: "load-in-iframe.myshopify.com",
          scope: "orders",
          access_token: "tok"
        })

      # `payment_routes/2` pipes the plans page through `:shopifex_browser`
      # (Phoenix's secure headers + this plug) and `:shopify_embedded`.
      conn =
        get(conn, "/payment/show-plans", %{
          "id_token" => Shopifex.Test.sign_session_token(shop.url)
        })

      assert html_response(conn, 200)
      assert Plug.Conn.get_resp_header(conn, "x-frame-options") == []

      assert Enum.sort(csp_headers(conn)) == [
               "base-uri 'self';",
               "frame-ancestors https://admin.shopify.com https://load-in-iframe.myshopify.com;"
             ]
    end
  end
end
