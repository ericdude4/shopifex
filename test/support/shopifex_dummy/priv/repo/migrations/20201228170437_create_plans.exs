defmodule ShopifexDummy.Repo.Migrations.CreatePlans do
  use Ecto.Migration

  def change do
    create table(:plans) do
      add :name, :string
      add :price, :string
      add :features, {:array, :string}
      add :grants, {:array, :string}
      add :test, :boolean, default: false
      add :type, :string, default: "recurring_application_charge"
      add :usages, :integer, null: true, default: nil

      timestamps()
    end

  end
end
