defmodule ShopifexWeb.CacheBodyReader do
  @moduledoc """
  Include `body_reader: {ShopifexWeb.CacheBodyReader, :read_body, []}` in your `endpoint.ex` file in Plug.Parser options

  Example:

  ```elixir
  ...
  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    body_reader: {ShopifexWeb.CacheBodyReader, :read_body, []},
    json_decoder: Phoenix.json_library()
  ```
  """
  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    conn = update_in(conn.assigns[:raw_body], &[body | &1 || []])
    {:ok, body, conn}
  end
end
