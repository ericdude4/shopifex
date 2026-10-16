defmodule ShopifexWeb.CacheBodyReaderTest do
  use ExUnit.Case, async: true

  import Plug.Test, only: [conn: 3]

  alias ShopifexWeb.CacheBodyReader

  test "caches the body and returns {:ok, ...} for a body within :length" do
    conn = conn(:post, "/webhook", ~s({"id":1}))

    assert {:ok, ~s({"id":1}), conn} = CacheBodyReader.read_body(conn, [])
    assert IO.iodata_to_binary(Enum.reverse(conn.assigns[:raw_body])) == ~s({"id":1})
  end

  test "returns {:more, ...} instead of crashing when the body exceeds :length" do
    # Regression: the previous single-clause {:ok, ...} match raised a
    # MatchError (a 500) for any body larger than Plug.Parsers' :length
    # budget; the contract is to pass {:more, ...} through so the parser
    # rejects with 413.
    body = String.duplicate("a", 100)
    conn = conn(:post, "/webhook", body)

    assert {:more, partial, conn} = CacheBodyReader.read_body(conn, length: 10)
    assert byte_size(partial) < byte_size(body)
    assert [_ | _] = conn.assigns[:raw_body]
  end
end
