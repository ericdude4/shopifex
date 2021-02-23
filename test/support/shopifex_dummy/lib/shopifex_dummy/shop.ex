defmodule ShopifexDummy.Shop do
  use Ecto.Schema
  import Ecto.Changeset

  schema "shops" do
    field(:url, :string)
    field(:scope, :string)
    field(:access_token, :string)

    timestamps()
  end

  @doc false
  def changeset(shop, attrs) do
    shop
    |> cast(attrs, [:url, :scope, :access_token])
    |> validate_required([:url, :scope, :access_token])
  end
end
