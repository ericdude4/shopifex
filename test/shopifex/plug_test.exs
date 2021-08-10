defmodule Shopifex.PlugTest do
  use ShopifexWeb.ConnCase
  alias ShopifexDummy.Shop

  setup [:shop_in_session]

  test "put_shop_in_session/2 puts shop in shopifex conn.private", %{conn: conn} do
    shop =
      conn
      |> Shopifex.Plug.current_shop()
      |> Map.put(:url, "FOO BAR")

    conn = Shopifex.Plug.put_shop_in_session(conn, shop)

    assert %Shop{url: "FOO BAR"} = Shopifex.Plug.current_shop(conn)
  end
end
