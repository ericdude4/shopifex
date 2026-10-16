defmodule Mix.Shopifex.Plan do
  def attrs(),
    do: [
      {:name, :string},
      {:price, :string},
      {:features, {:array, :string}},
      {:grants, {:array, :string}},
      {:test, :boolean, default: false},
      {:trial_days, :integer, default: 0},
      # Nullable: unlimited plans have no usage cap. `null: true` drives both
      # the migration column nullability and skipping the field in the
      # generated `validate_required/2`.
      {:usages, :integer, [null: true]},
      {:type, :string}
    ]

  def assocs(),
    do: []

  def indexes(),
    do: [
      {:name, true}
    ]
end
