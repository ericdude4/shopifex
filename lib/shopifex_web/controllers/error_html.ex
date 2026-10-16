defmodule ShopifexWeb.ErrorHTML do
  @moduledoc """
  Renders error pages. By default returns the status message derived from the
  template name (e.g. `"404.html"` -> "Not Found").
  """
  use ShopifexWeb, :html

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
