defmodule Shopifex.ShopsTest do
  use Shopifex.DataCase, async: true
  alias Shopifex.Shops
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney

  setup_all do
    HTTPoison.start()
  end

  @valid_shop_params %{
    url: "shopifex-test.myshopify.com",
    scope: "read_inventory,read_products,read_orders",
    access_token: "foo_dummy_token"
  }

  @valid_plan_params %{
    name: "Basic",
    price: "9.99",
    features: ["feature1"],
    grants: ["guard1"],
    type: "recurring_application_charge"
  }

  setup do
    shop = Shops.create_shop(@valid_shop_params)
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

  describe "schema helpers" do
    test "shop_schema/0 returns the configured shop schema" do
      assert Shops.shop_schema() == ShopifexDummy.Shop
    end

    test "grant_schema/0 returns the configured grant schema" do
      assert Shops.grant_schema() == ShopifexDummy.Shops.Grant
    end

    test "plan_schema/0 returns the configured plan schema" do
      assert Shops.plan_schema() == ShopifexDummy.Shops.Plan
    end

    test "repo/0 returns the configured repo" do
      assert Shops.repo() == ShopifexDummy.Repo
    end
  end

  describe "get_shop_by_url/1" do
    test "returns shop with matching url", %{shop: shop} do
      assert %ShopifexDummy.Shop{url: "shopifex-test.myshopify.com"} =
               Shops.get_shop_by_url(shop.url)
    end

    test "returns nil when shop does not exist" do
      assert nil == Shops.get_shop_by_url("nonexistent.myshopify.com")
    end
  end

  describe "get_url/1" do
    test "returns the url of the shop", %{shop: shop} do
      assert Shops.get_url(shop) == "shopifex-test.myshopify.com"
    end
  end

  describe "get_scope/1" do
    test "returns the scope of the shop", %{shop: shop} do
      assert Shops.get_scope(shop) == "read_inventory,read_products,read_orders"
    end
  end

  describe "get_scope_field/0" do
    test "returns the scope field atom" do
      assert Shops.get_scope_field() == :scope
    end
  end

  describe "create_shop/1" do
    test "creates a shop with valid params" do
      shop =
        Shops.create_shop(%{
          url: "new-shop.myshopify.com",
          scope: "read_orders",
          access_token: "token123"
        })

      assert %ShopifexDummy.Shop{url: "new-shop.myshopify.com"} = shop
    end
  end

  describe "update_shop/2" do
    test "updates a shop with valid params", %{shop: shop} do
      updated = Shops.update_shop(shop, %{scope: "write_orders"})
      assert updated.scope == "write_orders"
    end
  end

  describe "delete_shop/1" do
    test "deletes a shop", %{shop: shop} do
      Shops.delete_shop(shop)
      assert nil == Shops.get_shop_by_url(shop.url)
    end
  end

  describe "plans" do
    test "list_plans/0 returns empty list when no plans exist" do
      assert [] == Shops.list_plans()
    end

    test "list_plans/0 returns all plans" do
      {:ok, _} = Shops.create_plan(@valid_plan_params)
      assert [%ShopifexDummy.Shops.Plan{}] = Shops.list_plans()
    end

    test "list_plans_granting_guard/1 returns plans with the given guard" do
      {:ok, _} = Shops.create_plan(%{@valid_plan_params | grants: ["pro_guard"]})
      plans = Shops.list_plans_granting_guard("pro_guard")
      assert length(plans) == 1
      assert hd(plans).name == "Basic"
    end

    test "list_plans_granting_guard/1 returns empty list when no plans have the guard" do
      {:ok, _} = Shops.create_plan(@valid_plan_params)
      assert [] == Shops.list_plans_granting_guard("nonexistent_guard")
    end

    test "get_plan!/1 returns the plan with given id" do
      {:ok, plan} = Shops.create_plan(@valid_plan_params)
      assert %ShopifexDummy.Shops.Plan{id: id} = Shops.get_plan!(plan.id)
      assert id == plan.id
    end

    test "create_plan/1 with valid attrs creates a plan" do
      assert {:ok, %ShopifexDummy.Shops.Plan{name: "Basic"}} =
               Shops.create_plan(@valid_plan_params)
    end

    test "create_plan/1 with invalid attrs returns an error changeset" do
      assert {:error, %Ecto.Changeset{}} = Shops.create_plan(%{})
    end

    test "create_plan/0 with no args returns an error changeset" do
      assert {:error, %Ecto.Changeset{}} = Shops.create_plan()
    end

    test "update_plan/2 updates a plan" do
      {:ok, plan} = Shops.create_plan(@valid_plan_params)

      assert {:ok, %ShopifexDummy.Shops.Plan{name: "Premium"}} =
               Shops.update_plan(plan, %{name: "Premium"})
    end

    test "delete_plan/1 deletes a plan" do
      {:ok, plan} = Shops.create_plan(@valid_plan_params)
      assert {:ok, _} = Shops.delete_plan(plan)
      assert_raise Ecto.NoResultsError, fn -> Shops.get_plan!(plan.id) end
    end

    test "change_plan/1 returns a changeset for the plan" do
      {:ok, plan} = Shops.create_plan(@valid_plan_params)
      assert %Ecto.Changeset{} = Shops.change_plan(plan)
    end

    test "change_plan/2 returns a changeset with the given changes applied" do
      {:ok, plan} = Shops.create_plan(@valid_plan_params)
      changeset = Shops.change_plan(plan, %{name: "Updated"})
      assert %Ecto.Changeset{} = changeset
      assert changeset.changes.name == "Updated"
    end
  end

  describe "grants" do
    test "list_grants/0 returns empty list when no grants exist" do
      assert [] == Shops.list_grants()
    end

    test "list_grants/0 returns all grants", %{shop: shop} do
      {:ok, _} = Shops.create_grant(%{shop_id: shop.id, grants: ["guard1"]})
      assert [%ShopifexDummy.Shops.Grant{}] = Shops.list_grants()
    end

    test "get_grant!/1 returns the grant with given id", %{shop: shop} do
      {:ok, grant} = Shops.create_grant(%{shop_id: shop.id, grants: ["guard1"]})
      assert %ShopifexDummy.Shops.Grant{id: id} = Shops.get_grant!(grant.id)
      assert id == grant.id
    end

    test "create_grant/1 with valid attrs creates a grant", %{shop: shop} do
      assert {:ok, %ShopifexDummy.Shops.Grant{grants: ["guard1"]}} =
               Shops.create_grant(%{shop_id: shop.id, grants: ["guard1"]})
    end

    test "create_grant/1 with invalid attrs returns an error changeset" do
      assert {:error, %Ecto.Changeset{}} = Shops.create_grant(%{})
    end

    test "create_grant/0 with no args returns an error changeset" do
      assert {:error, %Ecto.Changeset{}} = Shops.create_grant()
    end

    test "update_grant/2 updates a grant", %{shop: shop} do
      {:ok, grant} = Shops.create_grant(%{shop_id: shop.id, grants: ["guard1"]})

      assert {:ok, %ShopifexDummy.Shops.Grant{grants: ["guard2"]}} =
               Shops.update_grant(grant, %{grants: ["guard2"]})
    end

    test "delete_grant/1 deletes a grant", %{shop: shop} do
      {:ok, grant} = Shops.create_grant(%{shop_id: shop.id, grants: ["guard1"]})
      assert {:ok, _} = Shops.delete_grant(grant)
      assert_raise Ecto.NoResultsError, fn -> Shops.get_grant!(grant.id) end
    end

    test "change_grant/1 returns a changeset for the grant", %{shop: shop} do
      {:ok, grant} = Shops.create_grant(%{shop_id: shop.id, grants: ["guard1"]})
      assert %Ecto.Changeset{} = Shops.change_grant(grant)
    end

    test "change_grant/2 returns a changeset with the given changes applied", %{shop: shop} do
      {:ok, grant} = Shops.create_grant(%{shop_id: shop.id, grants: ["guard1"]})
      changeset = Shops.change_grant(grant, %{grants: ["guard2"]})
      assert %Ecto.Changeset{} = changeset
      assert changeset.changes.grants == ["guard2"]
    end
  end
end
