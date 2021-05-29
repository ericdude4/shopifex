defmodule ShopifexWeb.PaymentView do
  use ShopifexWeb, :view

  def shop_url(%Plug.Conn{} = conn) do
    conn
    |> Shopifex.Plug.current_shop()
    |> Map.get(:url)
  end
end
