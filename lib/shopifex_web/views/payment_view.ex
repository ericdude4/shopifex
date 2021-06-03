defmodule ShopifexWeb.PaymentView do
  use ShopifexWeb, :view

  def available_plans(guard) do
    guard
    |> Shopifex.Shops.list_plans_granting_guard()
    |> Enum.map(fn guard ->
      Map.take(guard, [:id, :features, :grants, :name, :price, :type, :usages])
    end)
  end

  def shop_url(%Plug.Conn{} = conn) do
    conn
    |> Shopifex.Plug.current_shop()
    |> Map.get(:url)
  end
end
