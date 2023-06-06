defmodule Shopifex.PaymentGuardTest do
  use Shopifex.DataCase, async: true
  alias Shopifex.Shops
  alias ShopifexDummy.Shops.{PaymentGuard, Grant}

  setup do
    shop =
      Shops.create_shop(%{
        url: "shopifex-test.myshopify.com",
        scope: "read_inventory,read_products,read_orders",
        access_token: "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"
      })

    {:ok, plan} =
      Shops.create_plan(%{
        name: "Basic",
        price: "1.00",
        grants: ["restricted_feature"],
        features: ["gain access", "wow"]
      })

    {:ok, shop: shop, plan: plan}
  end

  describe "grant_for_guard/1" do
    setup %{plan: plan, shop: shop} do
      {:ok, _grant} = PaymentGuard.create_grant(shop, plan, 123)

      :ok
    end

    test "returns valid grant for guard from database", %{shop: shop} do
      assert %Grant{
               grants: ["restricted_feature"]
             } = PaymentGuard.grant_for_guard(shop, "restricted_feature")
    end

    test "returns nil when no grant present for guard", %{shop: shop} do
      assert PaymentGuard.grant_for_guard(shop, "another_restricted_feature") == nil
    end

    test "supports taking a list of grants instead of a shop as first parameter" do
      assert %Grant{
               grants: ["another_restricted_feature"]
             } =
               PaymentGuard.grant_for_guard(
                 [
                   %Grant{
                     grants: ["another_restricted_feature"],
                     remaining_usages: nil
                   }
                 ],
                 "another_restricted_feature"
               )
    end
  end

  describe "grants_for_shop/1" do
    setup %{plan: plan, shop: shop} do
      {:ok, _grant} = PaymentGuard.create_grant(shop, plan, 123)

      :ok
    end

    test "returns a list of all grants for the provided shop", %{shop: shop} do
      shop_id = shop.id

      [
        %ShopifexDummy.Shops.Grant{
          shop_id: ^shop_id,
          grants: ["restricted_feature"]
        }
      ] = PaymentGuard.grants_for_shop(shop)
    end
  end
end
