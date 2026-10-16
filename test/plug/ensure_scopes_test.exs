defmodule Shopifex.Plug.EnsureScopesTest do
  use ShopifexWeb.ConnCase

  setup do
    conn = build_conn(:get, "/my-route?foo=bar&fizz=buzz")
    {:ok, conn: conn}
  end

  setup [:shop_in_session]

  # Several tests change `config :shopifex, :scopes`; put it back so the rest
  # of the suite sees the dummy app's value.
  setup do
    previous = Application.get_env(:shopifex, :scopes)

    on_exit(fn ->
      if previous == nil,
        do: Application.delete_env(:shopifex, :scopes),
        else: Application.put_env(:shopifex, :scopes, previous)
    end)

    :ok
  end

  test "shop scopes matching shopifex config passes plug", %{
    conn: conn
  } do
    shop = Shopifex.Plug.current_shop(conn)
    Application.put_env(:shopifex, :scopes, shop.scope)

    conn = Shopifex.Plug.EnsureScopes.call(conn, [])

    refute conn.halted
  end

  test "raises an actionable error by default when scopes are missing", %{conn: conn} do
    assert_raise Shopifex.RuntimeError, ~r/missing required scopes/, fn ->
      Shopifex.Plug.EnsureScopes.call(conn, required_scopes: "read_orders")
    end
  end

  test "renders redirect page with location to Shopify OAuth update flow when opted in", %{
    conn: conn
  } do
    conn =
      Shopifex.Plug.EnsureScopes.call(conn,
        required_scopes: "read_orders",
        on_missing_scopes: :redirect
      )

    assert conn.halted
    assert html_response(conn, 200) =~ "Redirecting"

    assert conn.assigns.redirect_location =~
             "https://shopifex.myshopify.com/admin/oauth/authorize?client_id=thisisafakeapikey"
  end

  test "renders redirect page with exactly one doctype even when root layout is set", %{
    conn: conn
  } do
    defmodule DummyRootLayout do
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
      |> Phoenix.Controller.put_root_layout(html: {DummyRootLayout, :root})
      |> Shopifex.Plug.EnsureScopes.call(
        required_scopes: "read_orders",
        on_missing_scopes: :redirect
      )

    body = html_response(conn, 200)
    assert length(Regex.scan(~r/<!DOCTYPE html>/i, body)) == 1
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

  describe "scope list normalisation" do
    test "empty :scopes config requires nothing, even when the shop has scopes", %{conn: conn} do
      Application.put_env(:shopifex, :scopes, "")
      assert Shopifex.Shops.get_scope(Shopifex.Plug.current_shop(conn)) == "orders"

      refute Shopifex.Plug.EnsureScopes.call(conn, []).halted
    end

    test "nil :scopes config requires nothing", %{conn: conn} do
      Application.put_env(:shopifex, :scopes, nil)

      refute Shopifex.Plug.EnsureScopes.call(conn, []).halted
    end

    test "omitted :scopes config requires nothing", %{conn: conn} do
      Application.delete_env(:shopifex, :scopes)

      refute Shopifex.Plug.EnsureScopes.call(conn, []).halted
    end

    test "whitespace after commas in :scopes config matches a Shopify-formatted shop scope",
         %{conn: conn} do
      # Shopify's token response never contains spaces in `scope`.
      conn = with_shop_scope(conn, "read_products,write_products")
      Application.put_env(:shopifex, :scopes, "read_products, write_products")

      refute Shopifex.Plug.EnsureScopes.call(conn, []).halted
    end

    test ":required_scopes plug option accepts a list", %{conn: conn} do
      conn = with_shop_scope(conn, "read_products,write_products")

      refute Shopifex.Plug.EnsureScopes.call(conn,
               required_scopes: ["read_products", " write_products"]
             ).halted
    end

    test "a genuinely missing scope still raises, named without padding", %{conn: conn} do
      conn = with_shop_scope(conn, "read_products")
      Application.put_env(:shopifex, :scopes, "read_products, write_products")

      assert_raise Shopifex.RuntimeError, ~r/missing required scopes \["write_products"\]/, fn ->
        Shopifex.Plug.EnsureScopes.call(conn, [])
      end
    end

    test "legacy redirect with an empty :scopes config requests only the missing scope",
         %{conn: conn} do
      Application.put_env(:shopifex, :scopes, "")

      conn =
        Shopifex.Plug.EnsureScopes.call(conn,
          required_scopes: "read_orders",
          on_missing_scopes: :redirect
        )

      assert conn.halted
      assert redirect_scope_param(conn) == "read_orders"
    end

    test "legacy redirect joins the configured scopes without stray commas", %{conn: conn} do
      Application.put_env(:shopifex, :scopes, "orders, ")

      conn =
        Shopifex.Plug.EnsureScopes.call(conn,
          required_scopes: "read_orders",
          on_missing_scopes: :redirect
        )

      assert redirect_scope_param(conn) == "read_orders,orders"
    end
  end

  # Re-stores the shop's granted scope and rebuilds the session so the plug
  # sees it, as it would after a token exchange.
  defp with_shop_scope(conn, scope) do
    shop = Shopifex.Shops.update_shop(Shopifex.Plug.current_shop(conn), %{scope: scope})
    Shopifex.Plug.build_session(conn, shop, Shopifex.Plug.current_shopify_host(conn))
  end

  defp redirect_scope_param(conn) do
    %URI{query: query} = URI.parse(conn.assigns.redirect_location)
    URI.decode_query(query)["scope"]
  end
end
