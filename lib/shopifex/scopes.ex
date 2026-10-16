defmodule Shopifex.Scopes do
  @moduledoc """
  Normalises Shopify access-scope lists so every scope check in the library
  agrees on the same input.

  Shopify stores a shop's granted scopes as a comma-separated string with no
  whitespace (`"read_products,write_products"`). App config is hand-written and
  drifts from that format — a space after a comma, a trailing comma, an empty
  string or `nil` — and a bare `String.split/2` turns each of those into a
  phantom scope (`""` or `" write_products"`) that Shopify never grants.
  `split/1` trims every segment and drops empty ones, so an empty or `nil`
  scope list means "nothing required", never a required scope named `""`.
  """

  @typedoc """
  A scope list as configured or stored: a comma-separated string, a list of
  scope names, or `nil`.
  """
  @type scopes :: String.t() | [String.t()] | nil

  @doc """
  Splits `scopes` into a list of scope names, trimming whitespace and dropping
  empty segments.

  Accepts `nil` (returns `[]`), a comma-separated string, or a list of scope
  names — each element is trimmed and empty ones dropped, so a
  `required_scopes: ["read_orders"]` plug option works too.

  ## Examples

      iex> Shopifex.Scopes.split("read_products, write_products,")
      ["read_products", "write_products"]

      iex> Shopifex.Scopes.split("")
      []

      iex> Shopifex.Scopes.split(nil)
      []

      iex> Shopifex.Scopes.split([" read_orders", ""])
      ["read_orders"]
  """
  @spec split(scopes()) :: [String.t()]
  def split(nil), do: []
  def split(scopes) when is_binary(scopes), do: scopes |> String.split(",") |> normalise()
  def split(scopes) when is_list(scopes), do: normalise(scopes)

  @doc """
  Returns the scopes in `required` that `granted` does not contain, in the
  order they were required. Both arguments go through `split/1` first.

  ## Examples

      iex> Shopifex.Scopes.missing("read_products, write_products", "read_products")
      ["write_products"]

      iex> Shopifex.Scopes.missing("", "read_products")
      []

      iex> Shopifex.Scopes.missing(nil, nil)
      []
  """
  @spec missing(scopes(), scopes()) :: [String.t()]
  def missing(required, granted) do
    granted = split(granted)
    Enum.reject(split(required), &(&1 in granted))
  end

  defp normalise(segments) do
    segments
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
