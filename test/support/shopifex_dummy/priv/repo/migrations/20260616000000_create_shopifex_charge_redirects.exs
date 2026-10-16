defmodule ShopifexDummy.Repo.Migrations.CreateShopifexChargeRedirects do
  use Ecto.Migration

  def change do
    create table(:shopifex_charge_redirects, primary_key: false) do
      add(:charge_id, :bigint, primary_key: true)
      add(:redirect_after, :text, null: false)
      add(:inserted_at, :utc_datetime, null: false)
    end
  end
end
