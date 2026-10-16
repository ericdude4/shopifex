defmodule ShopifexWeb.AuthJSON do
  @moduledoc """
  JSON responses for the session plug (e.g. the `403` returned to
  unauthenticated API requests).
  """
  def render("403.json", %{message: message}) do
    %{message: message}
  end
end
