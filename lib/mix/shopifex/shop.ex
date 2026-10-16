defmodule Mix.Shopifex.Shop do
  def attrs(),
    do: [
      {:url, :string},
      {:access_token, :string},
      # Nullable so legacy / non-expiring installs round-trip. `null: true`
      # drives both the migration column nullability and skipping the field
      # in the generated `validate_required/2`.
      {:scope, :string, [null: true]},
      {:token_expires_at, :utc_datetime, [null: true]},
      {:refresh_token, :string, [null: true]},
      {:refresh_token_expires_at, :utc_datetime, [null: true]}
    ]

  def assocs(),
    do: [
      {:has_many, :grants, :grants}
    ]

  def indexes(),
    do: [
      {:url, true}
    ]
end
