defmodule Mix.Shopifex.Grant do
  def attrs(),
    do: [
      {:charge_id, :bigint, null: true},
      {:grants, {:array, :string}, null: false},
      {:remaining_usages, :integer, null: true},
      {:total_usages, :integer, null: true, default: 0}
    ]

  def assocs(),
    do: [
      {:belongs_to, :shop, :shops}
    ]

  def indexes(),
    do: [
      {:grants, :gin}
    ]
end
