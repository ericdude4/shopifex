defmodule Mix.Shopifex.Grant do
  def attrs(),
    do: [
      # Nullable: `Shopifex.Shops.create_shop_grant/2` never supplies a
      # charge_id, and unlimited plans (`plan.usages == nil`) leave
      # remaining_usages nil. `null: true` drives both the migration column
      # nullability and skipping the field in the generated
      # `validate_required/2`.
      {:charge_id, :bigint, [null: true]},
      {:grants, {:array, :string}},
      {:remaining_usages, :integer, [null: true]},
      {:total_usages, :integer, default: 0}
    ]

  def assocs(),
    do: [
      {:belongs_to, :shop, :shops}
    ]

  def indexes(),
    do: [
      {:grants, :gin},
      # Postgres does not auto-index foreign-key columns. `grant_for_guard/2`
      # runs on every payment-guarded request and filters by `shop_id`, so a
      # plain btree index here is the difference between an index scan and a
      # sequential scan that grows with the grants table.
      {:shop_id, :index}
    ]
end
