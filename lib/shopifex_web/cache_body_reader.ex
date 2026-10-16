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
    # Mirror Plug.Conn.read_body/2's full contract. The previous
    # single-clause `{:ok, body, conn} = ...` match raised a MatchError for
    # any body larger than Plug.Parsers' `:length` budget ({:more, ...}) and
    # for adapter-level failures ({:error, ...}) — a 500 instead of the 413
    # Plug.Parsers would return. Cache every chunk we read so the accumulated
    # `raw_body` stays byte-exact for webhook HMAC verification.
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        conn = update_in(conn.assigns[:raw_body], &[body | &1 || []])
        {:ok, body, conn}

      {:more, partial, conn} ->
        # Body exceeds the parser's :length — pass {:more, ...} through so
        # Plug.Parsers rejects with 413. The cached prefix is never HMAC'd
        # (the request doesn't reach the webhook plug).
        conn = update_in(conn.assigns[:raw_body], &[partial | &1 || []])
        {:more, partial, conn}

      {:error, _reason} = error ->
        error
    end
  end
end
