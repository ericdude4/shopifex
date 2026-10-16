defmodule Shopifex.ShopTest do
  @moduledoc """
  Covers `Shopifex.Shop` (the optional macro that lets a shop schema declare
  custom field names) and the `ShopsContext` path that honors it — the branch
  exercised when a schema defines the `shopifex_*_field/0` accessors. The default
  branch (plain schemas, what `mix shopifex.install` generates) is covered by
  `Shopifex.ShopsTest` via the hand-rolled dummy schema.
  """
  # async: false — the integration test swaps the global :shop_schema config.
  use ExUnit.Case, async: false

  defmodule CustomShop do
    use Shopifex.Shop,
      url_field: :installation_identifier,
      scope_field: :granted_scope,
      filters: [{:platform, "shopify"}],
      preloads: [:account]
  end

  defmodule DefaultShop do
    use Shopifex.Shop
  end

  describe "Shopifex.Shop macro" do
    test "injects the configured custom field accessors" do
      assert CustomShop.shopifex_url_field() == :installation_identifier
      assert CustomShop.shopifex_scope_field() == :granted_scope
      assert CustomShop.shopifex_filters() == [{:platform, "shopify"}]
      assert CustomShop.shopifex_preloads() == [:account]
    end

    test "falls back to defaults when no options are given" do
      assert DefaultShop.shopifex_url_field() == :url
      assert DefaultShop.shopifex_scope_field() == :scope
      assert DefaultShop.shopifex_filters() == []
      assert DefaultShop.shopifex_preloads() == []
    end
  end

  describe "ShopsContext honors a schema that uses Shopifex.Shop" do
    test "get_scope_field/0 returns the schema's custom scope_field" do
      previous = Application.fetch_env!(:shopifex, :shop_schema)
      Application.put_env(:shopifex, :shop_schema, CustomShop)
      on_exit(fn -> Application.put_env(:shopifex, :shop_schema, previous) end)

      assert Shopifex.Shops.get_scope_field() == :granted_scope
    end
  end
end
