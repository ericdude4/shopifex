defmodule ShopifexWeb.Flash do
  if Code.ensure_loaded?(Phoenix.Flash) do
    def get(conn, key) do
      Phoenix.Flash.get(conn, key)
    end
  else
    def get(conn, key) do
      Phoenix.Controller.get_flash(conn, key)
    end
  end
end
