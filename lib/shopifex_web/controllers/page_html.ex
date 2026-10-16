defmodule ShopifexWeb.PageHTML do
  @moduledoc """
  HTML rendered for app-bridge redirects (e.g. the scope-reinstall bounce in
  `Shopifex.Plug.EnsureScopes`).
  """
  use ShopifexWeb, :html

  embed_templates("page_html/*")

  def api_key, do: Application.get_env(:shopifex, :api_key)

  def shop_url(%Plug.Conn{} = conn) do
    conn
    |> Shopifex.Plug.current_shop()
    |> Shopifex.Shops.get_url()
  end
end
