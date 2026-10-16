defmodule ShopifexWeb.AuthHTML do
  @moduledoc """
  HTML rendered by `ShopifexWeb.AuthController` and the session plug —
  currently the store-selector / install page.
  """
  use ShopifexWeb, :html

  embed_templates("auth_html/*")

  def path_prefix, do: Application.get_env(:shopifex, :path_prefix, "")
  def app_name, do: Application.fetch_env!(:shopifex, :app_name)
end
