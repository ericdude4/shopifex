defmodule Shopifex.Shop do
  @moduledoc """
  A specification for how Shopifex is to interact with your Shopify
  shops table.

  ## Options
    * `:url_field` - the field which Shopifex will use to find a shop by url. Defaults to `:url`
    * `:filters` - a list of tuples to be used as filter keys which Shopifex will use when
      loading your shop from your database table. Defaults to `[]`

  ## Example:

  ```elixir
  defmodule MyApp.CommercePlatformInstallation do
    use MyApp.Schema
    use Shopifex.Shop, url_field: :installation_identifier, filters: [{:platform, "shopify"}, {:disabled_at, nil}]

    schema "commerce_platform_installations" do
      field(:installation_identifier, :string)
      field(:provider, :string, default: "shopify")
      field(:disabled_at, :utc_datetime)
      # ...
    end
  end
  ```
  """
  @default_url_field :url
  @default_filter_keys []

  defmacro __using__(opts \\ []) do
    url_key = Keyword.get(opts, :url_field, @default_url_field)
    filters = Keyword.get(opts, :filters, @default_filter_keys)

    quote do
      def shopifex_url_field(), do: unquote(url_key)
      def shopifex_filters(), do: unquote(filters)
    end
  end
end
