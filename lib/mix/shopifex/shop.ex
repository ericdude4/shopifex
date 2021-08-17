defmodule Mix.Shopifex.Shop do
  def attrs(),
    do: [
      {:url, :string, null: false},
      {:access_token, :string, null: false},
      {:scope, :string, null: false}
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
