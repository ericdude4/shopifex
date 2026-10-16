defmodule ShopifexDummyWeb.ErrorHTML do
  use ShopifexDummyWeb, :html

  def render("500.html", _assigns), do: "Internal Server Error"

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
