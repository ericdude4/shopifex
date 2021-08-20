defmodule Shopifex.Plug.EnsureScopes do
  @moduledoc """
  This plug ensures that the shop which is currently loaded in the session
  has all of the scopes which are defined under `config :shopifex, scopes: "foo"`.

  If the current shop does not have all the scopes, the conn is redirected to
  the Shopify OAuth update flow.

  Simply adding a new scope to your `:shopifex, scopes: "foo"` config will
  trigger an OAuth update with your installations.
  """
  import Plug.Conn
  import Phoenix.Controller
  require Logger

  def init(options) do
    # initialize options
    options
  end

  def call(conn, _) do
    case Shopifex.Plug.current_shop(conn) do
      nil ->
        raise(
          Shopifex.RuntimeError,
          """
          `Shopifex.Plug.EnsureScopes` must be placed in the pipeline after a plug which places a shop in the session; such as `Shopifex.Plug.ShopifySession` or `Shopifex.Plug.ShopifyWebhook`
          """
        )

      shop ->
        required_scopes = String.split(Application.get_env(:shopifex, :scopes), ",")
        shop_scopes = String.split(shop.scope, ",")

        case required_scopes -- shop_scopes do
          [] ->
            conn

          missing_scopes ->
            Logger.info(
              "Shop #{shop.url} is missing required scopes #{inspect(missing_scopes)}, initiating app update"
            )

            reinstall_url =
              "https://#{shop.url}/admin/oauth/authorize?client_id=#{Application.fetch_env!(:shopifex, :api_key)}&scope=#{Application.fetch_env!(:shopifex, :scopes)}&redirect_uri=#{Application.fetch_env!(:shopifex, :reinstall_uri)}"

            conn
            |> put_view(ShopifexWeb.PageView)
            |> put_layout({ShopifexWeb.LayoutView, "app.html"})
            |> render("redirect.html", redirect_location: reinstall_url)
            |> halt()
        end
    end
  end
end
