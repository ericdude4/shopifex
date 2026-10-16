defmodule ShopifexDummy.Repo.Migrations.CreateShopifexTokenRefreshLeases do
  use Ecto.Migration

  def change do
    create table(:shopifex_token_refresh_leases, primary_key: false) do
      add(:shop_url, :string, primary_key: true)
      add(:owner, :string, null: false)
      add(:lease_expires_at, :utc_datetime_usec, null: false)
    end
  end
end
