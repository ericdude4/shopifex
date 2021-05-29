defmodule Shopifex.Plug.ShopifySessionTest do
  use ShopifexWeb.ConnCase

  setup do
    conn =
      build_conn(:get, "?locale=fr")
      |> Plug.Conn.fetch_query_params()

    {:ok, conn: conn}
  end

  setup [:shop_in_session]

  test "locale is placed in session with locale parameter", %{conn: conn} do
    Shopifex.Plug.ShopifySession.call(conn, [])

    assert Gettext.get_locale() == "fr"
  end
end
