defmodule Mix.Shopifex.Shop do
  def attrs(),
    do: [
      {:url, :string, null: false},
      {:access_token, :string, null: false},
      {:scope, :string, null: false}
    ]

  def assocs(),
    do: [
      #  {:belongs_to, :owner, :users},
      #  {:has_many, :access_tokens, :access_tokens, foreign_key: :application_id}
    ]

  def indexes(),
    do: [
      {:url, true}
    ]
end
