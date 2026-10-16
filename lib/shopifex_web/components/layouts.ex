defmodule ShopifexWeb.Layouts do
  @moduledoc """
  Shopifex's built-in layouts, rendered as function components.

  Used by the auth / payment / scope-redirect pages via
  `put_layout(html: {ShopifexWeb.Layouts, :app})`.
  """
  use ShopifexWeb, :html

  embed_templates("layouts/*")

  @doc "Path prefix configured for the app (default `\"\"`)."
  def path_prefix, do: Application.get_env(:shopifex, :path_prefix, "")

  @doc "The configured app name."
  def app_name, do: Application.fetch_env!(:shopifex, :app_name)

  @doc "The app's Shopify API key, used for the App Bridge `shopify-api-key` meta tag."
  def api_key, do: Application.get_env(:shopifex, :api_key)
end
