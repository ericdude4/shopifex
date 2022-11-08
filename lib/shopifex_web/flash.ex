defmodule ShopifexWeb.Flash do
  @moduledoc false

  if Code.ensure_loaded?(Phoenix.Flash) do
    def get(assigns, kind) do
      Phoenix.Flash.get(assigns[:flash], kind)
    end
  else
    def get(assigns, kind) do
      Phoenix.Controller.get_flash(assigns[:conn], kind)
    end
  end
end
