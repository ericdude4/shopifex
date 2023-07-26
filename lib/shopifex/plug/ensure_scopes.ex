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

  def call(conn, opts \\ []) do
    case Shopifex.Plug.current_shop(conn) do
      nil ->
        raise(
          Shopifex.RuntimeError,
          """
          `Shopifex.Plug.EnsureScopes` must be placed in the pipeline after a plug which places a shop in the session; such as `Shopifex.Plug.ShopifySession` or `Shopifex.Plug.ShopifyWebhook`
          """
        )

      shop ->
        required_scopes =
          if Keyword.has_key?(opts, :required_scopes) do
            Keyword.get(opts, :required_scopes, "")
          else
            Application.get_env(:shopifex, :scopes, "")
          end
          |> String.split(",")

        shop_scopes =
          shop
          |> Shopifex.Shops.get_scope()
          |> String.split(",")

        case required_scopes -- shop_scopes do
          [] ->
            conn

          missing_scopes ->
            Logger.info(
              "Shop #{Shopifex.Shops.get_url(shop)} is missing required scopes #{inspect(missing_scopes)}, initiating app update"
            )

            base_required_scopes =
              :shopifex
              |> Application.get_env(:scopes, "")
              |> String.split(",")

            all_scopes_to_request = Enum.join(missing_scopes ++ base_required_scopes, ",")

            message = Keyword.get(opts, :message)

            reinstall_url =
              "https://#{Shopifex.Shops.get_url(shop)}/admin/oauth/authorize?client_id=#{Application.fetch_env!(:shopifex, :api_key)}&scope=#{all_scopes_to_request}&redirect_uri=#{Application.fetch_env!(:shopifex, :reinstall_uri)}"

            conn
            |> put_view(ShopifexWeb.PageView)
            |> put_layout({ShopifexWeb.LayoutView, "app.html"})
            |> render("redirect.html", redirect_location: reinstall_url, message: message)
            |> halt()
        end
    end
  end
end
