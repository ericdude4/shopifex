defmodule ShopifexDummy.Repo.Migrations.AddExpiringTokenFieldsToShops do
  use Ecto.Migration

  def change do
    alter table(:shops) do
      add(:refresh_token, :string)
      add(:access_token_expires_at, :utc_datetime)
      add(:refresh_token_expires_at, :utc_datetime)
    end
  end
end
