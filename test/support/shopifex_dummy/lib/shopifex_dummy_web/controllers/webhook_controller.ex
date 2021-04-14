defmodule ShopifexDummyWeb.WebhookController do
  use ShopifexDummyWeb, :controller
  use ShopifexWeb.WebhookController

  def handle_topic(conn, _shop, "foo/bar") do
    conn
    |> send_resp(200, "success")
  end

  @doc """
  Simply delete the shop record
  """
  def handle_topic(conn, shop, "app/uninstalled") do
    Shopifex.Shops.delete_shop(shop)

    conn
    |> send_resp(200, "success")
  end

  @doc """
  Mandatory Shopify shop data erasure GDPR webhook. Simply delete the shop record
  """
  def handle_topic(conn, shop, "shop/redact") do
    Shopifex.Shops.delete_shop(shop)

    conn
    |> send_resp(204, "")
  end

  @doc """
  Mandatory Shopify customer data erasure GDPR webhook. Simply delete the shop (customer) record
  """
  def handle_topic(conn, shop, "customers/redact") do
    Shopifex.Shops.delete_shop(shop)

    conn
    |> send_resp(204, "")
  end

  @doc """
  Mandatory Shopify customer data request GDPR webhook.
  """
  def handle_topic(conn, _shop, "customers/data_request") do
    # Send an email of the shop data to the customer.
    conn
    |> send_resp(202, "Accepted")
  end
end
