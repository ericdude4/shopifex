defmodule ShopifexDummy.Shop do
  use Ecto.Schema
  import Ecto.Changeset

  schema "shops" do
    field(:url, :string)
    field(:scope, :string)
    field(:access_token, :string)
    field(:token_expires_at, :utc_datetime)
    field(:refresh_token, :string)
    field(:refresh_token_expires_at, :utc_datetime)

    timestamps()
  end

  @doc false
  def changeset(shop, attrs) do
    shop
    |> cast(attrs, [
      :url,
      :scope,
      :access_token,
      :token_expires_at,
      :refresh_token,
      :refresh_token_expires_at
    ])
    |> validate_required([:url, :access_token])
  end
end
