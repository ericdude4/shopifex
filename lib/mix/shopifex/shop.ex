defmodule Mix.Shopifex.Shop do
  def attrs(),
    do: [
      {:url, :string},
      {:access_token, :string},
      {:scope, :string}
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
