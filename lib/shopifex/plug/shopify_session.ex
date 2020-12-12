defmodule Shopifex.Plug.ShopifySession do
  import Plug.Conn
  require Logger

  @moduledoc """
  Ensures that a valid store is currently loaded in the session and is accessible in your controllers/templates as `conn.private.shop`
  """

  def init(options) do
    # initialize options
    options
  end

  def call(conn, _) do
    shop_schema = Application.fetch_env!(:shopifex, :shop_schema)

    case Phoenix.Controller.get_flash(conn, :shop) do
      %{__struct__: ^shop_schema} = shop ->
        Logger.info("Found valid shop in session")

        conn
        |> put_shop_in_session(shop)

      _ ->
        Logger.info("No valid shop in session")

        conn
        |> Phoenix.Controller.redirect(to: "/auth?#{conn.query_string}")
        |> halt()
    end
  end

  def put_shop_in_session(conn, shop) do
    shop_url = shop.url

    Plug.Conn.put_private(conn, :shop_url, shop_url)
    |> Phoenix.Controller.put_flash(:shop_url, shop_url)
    |> Plug.Conn.put_private(:shop, shop)
    |> Phoenix.Controller.put_flash(:shop, shop)
  end
end
