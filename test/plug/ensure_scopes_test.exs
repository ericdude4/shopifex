defmodule Shopifex.Plug.EnsureScopesTest do
  use ShopifexWeb.ConnCase

  setup do
    conn = build_conn(:get, "/my-route?foo=bar&fizz=buzz")
    {:ok, conn: conn}
  end

  setup [:shop_in_session]

  test "shop scopes matching shopifex config passes plug", %{
    conn: conn
  } do
    shop = Shopifex.Plug.current_shop(conn)
    Application.put_env(:shopifex, :scopes, shop.scope)

    conn = Shopifex.Plug.EnsureScopes.call(conn, [])

    refute conn.halted
  end

  test "renders redirect page with location to Shopify OAuth update flow", %{
    conn: conn
  } do
    conn = Shopifex.Plug.EnsureScopes.call(conn, required_scopes: "read_orders")

    assert conn.halted
    assert html_response(conn, 200) =~ "WrappedRedirect"

    assert conn.assigns.redirect_location =~
             "https://shopifex.myshopify.com/admin/oauth/authorize?client_id=thisisafakeapikey"
  end

  test "throws error when shop not in session", %{
    conn: conn
  } do
    assert_raise Shopifex.RuntimeError, fn ->
      conn
      |> Map.put(:private, %{})
      |> Shopifex.Plug.EnsureScopes.call([])
    end
  end
end
