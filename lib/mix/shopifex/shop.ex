defmodule Mix.Shopifex.Shop do
  def attrs(),
    do: [
      {:url, :string},
      {:access_token, :string},
      {:scope, :string},
      {:refresh_token, :string},
      {:access_token_expires_at, :utc_datetime},
      {:refresh_token_expires_at, :utc_datetime}
    ]

  def assocs(),
    do: [
      {:has_many, :grants, :grants}
    ]

  def indexes(),
    do: [
      {:url, true}
    ]
end
