defmodule Mix.Shopifex.MigrationTest do
  use ExUnit.Case, async: true

  test "fresh-install migration includes the token refresh lease table" do
    migration =
      Mix.Shopifex.Migration.gen("CreateShopifyTables", "shopify", %{
        repo: ShopifexDummy.Repo,
        binary_id: false
      })

    assert migration =~ "create table(:shopifex_token_refresh_leases, primary_key: false)"
    assert migration =~ "add :shop_url, :string, primary_key: true"
    assert migration =~ "add :owner, :string, null: false"
    assert migration =~ "add :lease_expires_at, :utc_datetime_usec, null: false"
  end

  test "fresh-install migration includes the charge redirects table" do
    migration =
      Mix.Shopifex.Migration.gen("CreateShopifyTables", "shopify", %{
        repo: ShopifexDummy.Repo,
        binary_id: false
      })

    assert migration =~ "create table(:shopifex_charge_redirects, primary_key: false)"
    assert migration =~ "add :charge_id, :bigint, primary_key: true"
    assert migration =~ "add :redirect_after, :text, null: false"
    assert migration =~ "add :inserted_at, :utc_datetime, null: false"
  end

  test "grants -> shops reference cascades deletes so Shops.delete_shop/1 doesn't raise a FK error" do
    migration =
      Mix.Shopifex.Migration.gen("CreateShopifyTables", "shopify", %{
        repo: ShopifexDummy.Repo,
        binary_id: false
      })

    assert migration =~ "references(:shopify_shops, on_delete: :delete_all)"
    refute migration =~ "on_delete: :nothing"
  end
end
