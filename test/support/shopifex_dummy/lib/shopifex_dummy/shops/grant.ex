defmodule ShopifexDummy.Shops.Grant do
  use Ecto.Schema
  import Ecto.Changeset
  alias ShopifexDummy.Shop

  schema "grants" do
    field(:charge_id, :integer)
    field(:grants, {:array, :string})
    field(:remaining_usages, :integer)
    field(:total_usages, :integer, default: 0)

    belongs_to(:shop, Shop)

    timestamps()
  end

  @doc false
  def changeset(grant, attrs) do
    grant
    |> cast(attrs, [:charge_id, :grants, :remaining_usages, :total_usages, :shop_id])
    |> validate_required([:grants, :shop_id])
  end
end
