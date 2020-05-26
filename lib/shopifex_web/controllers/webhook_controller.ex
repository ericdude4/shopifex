defmodule ShopifexWeb.WebhookController do
  @moduledoc """
  You can use this module inside of another one of your application controllers.
  The conn, shop and topic will be called by handle_topic/3 which you can define in your parent controller.

  Example:

  ```elixir
  use ShopifexWeb.WebhookController

  def handle_topic(conn, shop, "app/uninstalled") do
    Shopifex.Shops.delete_shop(shop)

    conn
    |> send_resp(200, "success")
  end
  ```
  """
  defmacro __using__(_opts) do
    quote do
      def action(conn, _) do
        [topic] = Plug.Conn.get_req_header(conn, "x-shopify-topic")
        [shop_url] = Plug.Conn.get_req_header(conn, "x-shopify-shop-domain")

        case Shopifex.Shops.get_shop_by_url(shop_url) do
          nil ->
            conn
            |> send_resp(200, "success")

          shop ->
            handle_topic(conn, shop, topic)
        end
      end
    end
  end
end
