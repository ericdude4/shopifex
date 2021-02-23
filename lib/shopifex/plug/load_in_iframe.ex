defmodule Shopifex.Plug.LoadInIframe do
  def init(options) do
    # initialize options
    options
  end

  @doc """
  This allows your application to load inside of an iframe by deleting the x-frame-options response header
  """
  def call(conn, _) do
    Plug.Conn.delete_resp_header(conn, "x-frame-options")
  end
end
