defmodule Shopifex.Shops do
  import Ecto.Query, warn: false
  require Logger

  @moduledoc """
  This module acts as the context for any database interaction from within the Shopifex
  package.
  """

  def shop_schema, do: Application.fetch_env!(:shopifex, :shop_schema)
  def payment_schema, do: Application.fetch_env!(:shopifex, :payment_schema)
  def repo, do: Application.fetch_env!(:shopifex, :repo)

  def get_shop_by_url(url) do
    from(s in shop_schema(),
      where: s.url == ^url
    )
    |> repo().one()
  end

  def create_shop(params) do
    shop_schema().changeset(struct!(shop_schema()), params)
    |> repo().insert!()
  end

  def update_shop(params, shop) do
    shop_schema().changeset(shop, params)
    |> repo().update!()
  end

  def delete_shop(shop) do
    repo().delete!(shop)
  end

  def create_shop_payment(shop, identifier) do
    payment_schema().changeset(struct!(payment_schema()), %{shop: shop, identifier: identifier})
    |> repo().insert!()
  end

  @doc """
  Check the webhooks set on the shop, then compare that to the required webhooks based on the current
  status of the shop.
  """
  def configure_webhooks(shop) do
    {:ok, webhooks_response} =
      Shopify.session(shop.url, shop.access_token)
      |> Shopify.Webhook.all()

    webhooks = webhooks_response.data

    current_webhook_topics =
      webhooks
      |> Enum.map(& &1.topic)

    Logger.info(
      "All current webhook topics for #{shop.url}: #{Enum.join(current_webhook_topics, ", ")}"
    )

    current_webhook_topics = MapSet.new(current_webhook_topics)

    topics = MapSet.new(Application.fetch_env!(:shopifex, :webhook_topics))

    # Make sure all the required topics are conifgured.
    subscribe_to_topics = MapSet.difference(topics, current_webhook_topics)

    Enum.each(subscribe_to_topics, fn topic ->
      Logger.info("subscribing to topic #{topic}")
      create_webhook(shop, topic)
    end)
  end

  defp create_webhook(shop, topic) do
    {:ok, _response} =
      HTTPoison.post(
        "https://#{shop.url}/admin/webhooks.json",
        Jason.encode!(%{
          webhook: %{
            topic: topic,
            address: "#{Application.get_env(:shopifex, :webhook_uri)}",
            format: "json"
          }
        }),
        "X-Shopify-Access-Token": shop.access_token,
        "Content-Type": "application/json"
      )
  end
end
