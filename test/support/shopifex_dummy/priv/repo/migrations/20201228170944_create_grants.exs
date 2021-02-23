defmodule ShopifexDummy.Repo.Migrations.CreateGrants do
  use Ecto.Migration

  def change do
    create table(:grants) do
      add(:charge_id, :bigint)
      add(:grants, {:array, :string})
      add(:shop_id, references(:shops, on_delete: :nilify_all))
      add(:remaining_usages, :integer, null: true)
      add(:total_usages, :integer, default: 0)

      timestamps()
    end

    create(index(:grants, [:shop_id]))
  end
end
