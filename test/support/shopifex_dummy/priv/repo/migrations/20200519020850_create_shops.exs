defmodule ShopifexDummy.Repo.Migrations.CreateShops do
  use Ecto.Migration

  def change do
    create table(:shops) do
      add :url, :string
      add :scope, :string
      add :access_token, :string

      timestamps()
    end
  end
end
