defmodule ShopifexWeb do
  @moduledoc """
  The entrypoint for the Shopifex web interface — controllers and
  function-component HTML modules.

  This can be used in your application as:

      use ShopifexWeb, :controller
      use ShopifexWeb, :html

  The definitions below will be executed for every controller / HTML module,
  so keep them short and clean, focused on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define any helper function in modules
  and import those modules here.
  """

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]
      use Gettext, backend: ShopifexWeb.Gettext

      import Plug.Conn
    end
  end

  @doc """
  HTML rendering — Phoenix 1.7+ function components. `use ShopifexWeb, :html`
  brings in `Phoenix.Component` (`~H`, `embed_templates`, `attr/3`) plus the
  HTML helpers shared across Shopifex's `*HTML` modules and layouts.
  """
  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller, only: [get_csrf_token: 0]

      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      use Gettext, backend: ShopifexWeb.Gettext
      import Phoenix.HTML
    end
  end

  @doc """
  When used, dispatch to the appropriate controller / html helper.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
