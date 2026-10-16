defmodule ShopifexDummy.Repo.Migrations.AddTokenLifecycleToShops do
  use Ecto.Migration

  # Additive upgrade migration matching what installers on older Shopifex
  # versions need to run to adopt expiring offline access tokens. All columns
  # are nullable so legacy / non-expiring installs round-trip unchanged.
  def change do
    alter table(:shops) do
      add(:token_expires_at, :utc_datetime)
      add(:refresh_token, :string)
      add(:refresh_token_expires_at, :utc_datetime)
    end
  end
end
