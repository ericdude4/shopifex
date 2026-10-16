defmodule ShopifexDummyWeb.ProxyController do
  @moduledoc """
  Exercises the `:shopify_proxy` pipeline end-to-end: the response reflects
  whatever `Shopifex.Plug.current_shop/1` resolved (via `LoadProxyShop`).
  """
  use ShopifexDummyWeb, :controller

  def show(conn, _params) do
    case Shopifex.Plug.current_shop(conn) do
      nil -> send_resp(conn, 200, "no shop")
      shop -> send_resp(conn, 200, "shop: #{shop.url}")
    end
  end
end
