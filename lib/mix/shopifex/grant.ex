defmodule Mix.Shopifex.Grant do
  def attrs(),
    do: [
      {:charge_id, :bigint},
      {:grants, {:array, :string}},
      {:remaining_usages, :integer},
      {:total_usages, :integer, default: 0}
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
