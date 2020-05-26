defmodule Shopifex.Plug.ShopifySession do
  import Plug.Conn

  def init(options) do
    # initialize options
    options
  end

  @doc """
  Ensures that a valid store is currently loaded in the session and is accessible in your controllers/templates as `conn.private.shop`
  """
  def call(conn, _) do
    shop_schema = Application.fetch_env!(:shopifex, :shop_schema)

    case Phoenix.Controller.get_flash(conn, :shop) do
      %{__struct__: ^shop_schema} = shop ->
        conn
        |> custom_fetch_flash()

      _ ->
        conn
        |> Phoenix.Controller.redirect(to: "/auth")
        |> halt()
    end
  end

  @doc """
  This maintains the Shopify sesson as the user navigates around your application
  """
  defp custom_fetch_flash(conn, _opts \\ []) do
    session_flash = Plug.Conn.get_session(conn, "phoenix_flash")
    conn = Plug.Conn.put_private(conn, :phoenix_flash, session_flash || %{})

    register_before_send(conn, fn conn ->
      flash = conn.private.phoenix_flash
      flash_size = map_size(flash)

      cond do
        is_nil(session_flash) and flash_size == 0 ->
          conn

        flash_size > 0 and conn.status in 300..308 ->
          Plug.Conn.put_session(conn, "phoenix_flash", flash)

        flash_size > 0 and conn.status in 200..299 ->
          flash = Map.take(flash, ["shop_url", "shop"])
          Plug.Conn.put_session(conn, "phoenix_flash", flash)

        true ->
          Plug.Conn.delete_session(conn, "phoenix_flash")
      end
    end)
  end
end
