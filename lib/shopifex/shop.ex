defmodule Shopifex.Shop do
  @moduledoc """
  A specification for how Shopifex is to interact with your Shopify
  shops table.

  ## Options
    * `:url_field` - the field which Shopifex will use to find a shop by url. Defaults to `:url`
    * `:filters` - a list of tuples to be used as filter keys which Shopifex will use when
      loading your shop from your database table. Defaults to `[]`
    * `:preloads` - a list of preloads which Shopifex will pass unchanged to `MyApp.Repo.preload/2`
    * `:refresh_token_field` - the field holding the offline access token's refresh token. Defaults to `:refresh_token`
    * `:access_token_expires_at_field` - the `:utc_datetime` field holding the access token expiry. Defaults to `:access_token_expires_at`
    * `:refresh_token_expires_at_field` - the `:utc_datetime` field holding the refresh token expiry. Defaults to `:refresh_token_expires_at`

  The three token expiry fields are only used when
  `config :shopifex, expiring_offline_access_tokens: true` is set. See `Shopifex.OAuth`.

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
  @default_scope_field :scope
  @default_filter_keys []
  @default_preloads []
  @default_refresh_token_field :refresh_token
  @default_access_token_expires_at_field :access_token_expires_at
  @default_refresh_token_expires_at_field :refresh_token_expires_at

  defmacro __using__(opts \\ []) do
    url_key = Keyword.get(opts, :url_field, @default_url_field)
    scope_key = Keyword.get(opts, :scope_field, @default_scope_field)
    filters = Keyword.get(opts, :filters, @default_filter_keys)
    preloads = Keyword.get(opts, :preloads, @default_preloads)
    refresh_token_key = Keyword.get(opts, :refresh_token_field, @default_refresh_token_field)

    access_token_expires_at_key =
      Keyword.get(opts, :access_token_expires_at_field, @default_access_token_expires_at_field)

    refresh_token_expires_at_key =
      Keyword.get(opts, :refresh_token_expires_at_field, @default_refresh_token_expires_at_field)

    quote do
      def shopifex_url_field(), do: unquote(url_key)
      def shopifex_scope_field(), do: unquote(scope_key)
      def shopifex_filters(), do: unquote(filters)
      def shopifex_preloads(), do: unquote(preloads)
      def shopifex_refresh_token_field(), do: unquote(refresh_token_key)
      def shopifex_access_token_expires_at_field(), do: unquote(access_token_expires_at_key)
      def shopifex_refresh_token_expires_at_field(), do: unquote(refresh_token_expires_at_key)
    end
  end
end
