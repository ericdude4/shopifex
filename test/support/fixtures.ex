defmodule Shopifex.Fixtures do
  @moduledoc """
  Fixtures for the tests
  """
  def shop_in_session(%{conn: conn}) do
    shop =
      Shopifex.Shops.create_shop(%{
        url: "shopifex.myshopify.com",
        scope: "orders",
        access_token: "asdf1234"
      })

    conn = Plug.Conn.put_private(conn, :shop, shop)

    {:ok, conn: conn, shop: shop}
  end
end
