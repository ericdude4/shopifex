defmodule ShopifexWeb.ErrorJSON do
  @moduledoc """
  Renders JSON errors. By default returns `%{errors: %{detail: <status message>}}`.
  """
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
