defmodule Shopifex.Plug.FetchFlash do
  @moduledoc """
  Fetches the flash into `conn.assigns.flash`.

  Provided for backwards compatibility with earlier versions of Shopifex.
  In modern Phoenix applications (Phoenix >= 1.7), flash is stored in
  `conn.assigns.flash`, and this plug delegates directly to
  `Phoenix.Controller.fetch_flash/2`.
  """

  @doc false
  def init(options), do: options

  @doc false
  def call(conn, options) do
    Phoenix.Controller.fetch_flash(conn, options)
  end
end
