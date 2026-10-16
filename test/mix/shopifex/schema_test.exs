defmodule Mix.Shopifex.SchemaTest do
  # Not async: create_schema_files/3 writes to paths relative to the process
  # cwd, so this test shells out via File.cd!/2 to a scratch directory.
  use ExUnit.Case, async: false

  alias Mix.Shopifex.{Migration, Schema}

  @context_app :schema_test_app
  @namespace "shopify"
  @app_base SchemaTestApp
  @shop_module Module.concat([@app_base, ShopifyShops, ShopifyShop])
  @plan_module Module.concat([@app_base, ShopifyShops, ShopifyPlan])
  @grant_module Module.concat([@app_base, ShopifyShops, ShopifyGrant])
  @migration_module ShopifexDummy.Repo.Migrations.CreateShopifyTables

  defp purge(module) do
    :code.delete(module)
    :code.purge(module)
  end

  test "generated Shop, Plan and Grant schemas compile and produce working changesets" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "shopifex_schema_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    File.cd!(tmp_dir, fn ->
      Schema.create_schema_files(@context_app, @namespace, binary_id: false)
    end)

    shop_path = Path.join(tmp_dir, "lib/schema_test_app/shopify_shops/shopify_shop.ex")
    plan_path = Path.join(tmp_dir, "lib/schema_test_app/shopify_shops/shopify_plan.ex")
    grant_path = Path.join(tmp_dir, "lib/schema_test_app/shopify_shops/shopify_grant.ex")

    assert File.exists?(shop_path)
    assert File.exists?(plan_path)
    assert File.exists?(grant_path)

    on_exit(fn ->
      Enum.each([@shop_module, @plan_module, @grant_module], &purge/1)
    end)

    # belongs_to/has_many referencing a not-yet-defined module compiles fine
    # in Ecto, so order doesn't matter here.
    Code.compile_string(File.read!(shop_path))
    Code.compile_string(File.read!(plan_path))
    Code.compile_string(File.read!(grant_path))

    # apply/3 (rather than @grant_module.changeset/2) sidesteps a spurious
    # compiler warning: the module is only defined dynamically above, via
    # Code.compile_string/1, so it doesn't exist yet when this file itself
    # is compiled.
    grant_changeset =
      apply(@grant_module, :changeset, [
        struct!(@grant_module),
        %{
          shop_id: 1,
          grants: ["x"],
          remaining_usages: nil,
          charge_id: nil,
          total_usages: 0
        }
      ])

    assert grant_changeset.valid?

    plan_changeset =
      apply(@plan_module, :changeset, [
        struct!(@plan_module),
        %{
          name: "Pro",
          price: "9.99",
          features: ["a"],
          grants: ["x"],
          type: "recurring_application_charge"
        }
      ])

    assert plan_changeset.valid?
  end

  test "generated migration compiles" do
    migration =
      Migration.gen("CreateShopifyTables", @namespace, %{
        repo: ShopifexDummy.Repo,
        binary_id: false
      })

    on_exit(fn -> purge(@migration_module) end)

    Code.compile_string(migration)

    assert Code.ensure_loaded?(@migration_module)
  end
end
