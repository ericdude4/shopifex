defmodule ShopifexWeb.AuthView do
  use ShopifexWeb, :view

  def render("403.json", %{message: message}) do
    %{message: message}
  end
end
