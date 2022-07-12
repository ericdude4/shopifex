defmodule Mix.Shopifex.Plan do
  def attrs(),
    do: [
      {:name, :string},
      {:price, :string},
      {:features, {:array, :string}},
      {:grants, {:array, :string}},
      {:test, :boolean, default: false},
      {:trial_days, :integer, default: 0},
      {:usages, :integer},
      {:type, :string}
    ]

  def assocs(),
    do: []

  def indexes(),
    do: [
      {:name, true}
    ]
end
