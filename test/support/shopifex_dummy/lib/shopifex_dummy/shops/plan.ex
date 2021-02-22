defmodule ShopifexDummy.Shops.Plan do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:id, :features, :grants, :name, :price, :type, :usages]}

  schema "plans" do
    field :features, {:array, :string}
    field :grants, {:array, :string}
    field :name, :string
    field :price, :string
    field :test, :boolean, default: false
    field :type, :string, default: "recurring_application_charge"
    field :usages, :integer

    timestamps()
  end

  @doc false
  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [:name, :price, :features, :grants, :test, :type, :usages])
    |> validate_required([:name, :price, :features, :grants, :type, :usages])
  end
end
