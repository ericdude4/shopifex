defmodule Shopifex.ShopsTest do
  use Shopifex.DataCase, async: true
  alias Shopifex.Shops
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney

  setup_all do
    HTTPoison.start()
  end

  setup do
    shop =
      Shops.create_shop(%{
        url: "shopifex-test.myshopify.com",
        scope: "read_inventory,read_products,read_orders",
        access_token: "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"
      })

    {:ok, shop: shop}
  end

  describe "configure_webhooks/1" do
    test "subscribes shop to webhooks which it isn't subscribed to", %{shop: shop} do
      use_cassette "default_webhooks" do
        assert {:ok,
                [
                  %{
                    topic: "app/uninstalled"
                  }
                ]} = Shops.get_current_webhooks(shop)
      end

      use_cassette "configure_webhooks", match_requests_on: [:request_body] do
        assert [
                 %{
                   topic: "orders/create"
                 },
                 %{
                   topic: "carts/update"
                 }
               ] = Shops.configure_webhooks(shop)
      end

      use_cassette "all_webhooks" do
        assert {:ok,
                [
                  %{
                    topic: "app/uninstalled"
                  },
                  %{
                    topic: "carts/update"
                  },
                  %{
                    topic: "orders/create"
                  }
                ]} = Shops.get_current_webhooks(shop)
      end
    end
  end
end
