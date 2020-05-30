defmodule Shopifex.Plug.FetchFlash do
  import Plug.Conn

  @moduledoc """
  Fetches the flash in a way which maintains the session within Shopify iFrame
  """

  def init(options) do
    # initialize options
    options
  end

  def call(conn, _) do
    session_flash = Plug.Conn.get_session(conn, "phoenix_flash")
    conn = persist_flash(conn, session_flash || %{})

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

  defp persist_flash(conn, value) do
    Plug.Conn.put_private(conn, :phoenix_flash, value)
  end
end
