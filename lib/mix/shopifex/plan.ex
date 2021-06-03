defmodule Mix.Shopifex.Plan do
  def attrs(),
    do: [
      {:name, :string, null: false},
      {:price, :string, null: false},
      {:features, {:array, :string}, null: false},
      {:grants, {:array, :string}, null: false},
      {:test, :boolean, default: false},
      {:usages, :integer, null: true},
      {:type, :string, null: false}
    ]

  def assocs(),
    do: []

  def indexes(),
    do: [
      {:name, true}
    ]
end
