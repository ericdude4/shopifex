defmodule Shopifex.Plug.ShopifySession do
  import Plug.Conn

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
      %{__struct__: ^shop_schema} = _shop ->
        conn
        |> put_shop_in_session()

      _ ->
        conn
        |> Phoenix.Controller.redirect(to: "/auth?#{conn.query_string}")
        |> halt()
    end
  end

  defp put_shop_in_session(conn, _opts \\ []) do
    shop_url = Phoenix.Controller.get_flash(conn, :shop_url)
    shop = Phoenix.Controller.get_flash(conn, :shop)

    Plug.Conn.put_private(conn, :shop_url, shop_url)
    |> Phoenix.Controller.put_flash(:shop_url, shop_url)
    |> Plug.Conn.put_private(:shop, shop)
    |> Phoenix.Controller.put_flash(:shop, shop)
  end
end
