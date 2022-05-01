defmodule ShopifexWeb.PaymentView do
  use ShopifexWeb, :view

  @payment_guard Application.compile_env(:shopifex, :payment_guard)

  def available_plans(shop, guard) do
    shop
    |> @payment_guard.list_available_plans_for_guard(guard)
    |> Enum.map(fn guard ->
      Map.take(guard, [:id, :features, :grants, :name, :price, :type, :usages])
    end)
    |> Jason.encode!()
  end

  def shop_url(%Plug.Conn{} = conn) do
    conn
    |> Shopifex.Plug.current_shop()
    |> Shopifex.Shops.get_url()
  end
end
