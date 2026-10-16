defmodule Shopifex.PaymentGuardTest do
  use Shopifex.DataCase, async: false
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

    test "prefers unlimited grant over metered grant", %{shop: shop} do
      {:ok, metered} =
        Shops.create_grant(%{
          shop_id: shop.id,
          charge_id: 1001,
          grants: ["feature_multi"],
          remaining_usages: 10,
          total_usages: 0
        })

      {:ok, unlimited} =
        Shops.create_grant(%{
          shop_id: shop.id,
          charge_id: 1002,
          grants: ["feature_multi"],
          remaining_usages: nil,
          total_usages: 0
        })

      # From database
      selected = PaymentGuard.grant_for_guard(shop, "feature_multi")
      assert selected.id == unlimited.id
      assert selected.remaining_usages == nil

      # From list of grants
      selected_from_list = PaymentGuard.grant_for_guard([metered, unlimited], "feature_multi")
      assert selected_from_list.id == unlimited.id
    end

    test "does not leak another shop's metered grant", %{shop: shop} do
      other_shop =
        Shops.create_shop(%{
          url: "other-shop.myshopify.com",
          scope: "read_products",
          access_token: "shpat_other_shop_token"
        })

      {:ok, _metered_grant} =
        Shops.create_grant(%{
          shop_id: other_shop.id,
          charge_id: 999,
          grants: ["restricted_feature"],
          remaining_usages: 10,
          total_usages: 0
        })

      grant = PaymentGuard.grant_for_guard(shop, "restricted_feature")
      assert grant.shop_id == shop.id

      assert PaymentGuard.grant_for_guard(other_shop, "nonexistent_for_other") == nil
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

  describe "use_grant/2 concurrency and limits" do
    test "10 concurrent tasks decrementing a grant with 5 usages: exactly 5 succeed, 5 return nil",
         %{shop: shop} do
      {:ok, grant} =
        Shops.create_grant(%{
          shop_id: shop.id,
          charge_id: 555,
          grants: ["concurrent_op"],
          remaining_usages: 5,
          total_usages: 0
        })

      results =
        1..10
        |> Enum.map(fn _ ->
          Task.async(fn ->
            PaymentGuard.use_grant(shop, grant)
          end)
        end)
        |> Enum.map(&Task.await/1)

      successful = Enum.reject(results, &is_nil/1)
      failed = Enum.filter(results, &is_nil/1)

      assert length(successful) == 5
      assert length(failed) == 5

      final_grant = Repo.get!(Grant, grant.id)
      assert final_grant.remaining_usages == 0
      assert final_grant.total_usages == 5
    end

    test "unlimited grant only increments total_usages", %{shop: shop} do
      {:ok, grant} =
        Shops.create_grant(%{
          shop_id: shop.id,
          charge_id: 777,
          grants: ["unlimited_op"],
          remaining_usages: nil,
          total_usages: 0
        })

      updated = PaymentGuard.use_grant(shop, grant)
      assert updated.remaining_usages == nil
      assert updated.total_usages == 1

      updated2 = PaymentGuard.use_grant(shop, grant)
      assert updated2.remaining_usages == nil
      assert updated2.total_usages == 2

      final_grant = Repo.get!(Grant, grant.id)
      assert final_grant.remaining_usages == nil
      assert final_grant.total_usages == 2
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

    test "only returns grants belonging to the provided shop", %{shop: shop} do
      other_shop =
        Shops.create_shop(%{
          url: "other-shop.myshopify.com",
          scope: "read_products",
          access_token: "shpat_other_shop_token"
        })

      {:ok, _metered_grant} =
        Shops.create_grant(%{
          shop_id: other_shop.id,
          charge_id: 999,
          grants: ["restricted_feature"],
          remaining_usages: 10,
          total_usages: 0
        })

      grants = PaymentGuard.grants_for_shop(shop)

      assert grants != []
      assert Enum.all?(grants, &(&1.shop_id == shop.id))
    end
  end
end
