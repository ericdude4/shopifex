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

  # Mandatory Shopify shop data erasure GDPR webhook. Simply delete the shop record
  def handle_topic(conn, shop, "shop/redact") do
    Shopifex.Shops.delete_shop(shop)

    conn
    |> send_resp(204, "")
  end

  # Mandatory Shopify customer data erasure GDPR webhook. Simply delete the shop (customer) record
  def handle_topic(conn, shop, "customers/redact") do
    Shopifex.Shops.delete_shop(shop)

    conn
    |> send_resp(204, "")
  end

  # Mandatory Shopify customer data request GDPR webhook.
  def handle_topic(conn, _shop, "customers/data_request") do
    # Send an email of the shop data to the customer.
    conn
    |> send_resp(202, "Accepted")
  end
  ```
  """
  defmacro __using__(_opts) do
    quote do
      plug(:assign_shopify_topic)

      defp assign_shopify_topic(conn, _) do
        [topic] = Plug.Conn.get_req_header(conn, "x-shopify-topic")
        Plug.Conn.assign(conn, :shopify_topic, topic)
      end

      def action(conn, _),
        do: handle_topic(conn, Shopifex.Plug.current_shop(conn), conn.assigns[:shopify_topic])
    end
  end
end
