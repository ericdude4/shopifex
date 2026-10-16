defmodule Shopifex.Plug.ShopifyApiAuthTest do
  use Shopifex.DataCase, async: false

  alias Shopifex.Plug.ShopifyApiAuth

  @shop "api-auth.myshopify.com"

  defp api_conn do
    Plug.Test.conn(:get, "/api/x") |> Plug.Conn.fetch_query_params()
  end

  test "401 with the App Bridge retry header when no/invalid token is present" do
    conn = ShopifyApiAuth.call(api_conn(), [])

    assert conn.halted
    assert conn.status == 401
    # App Bridge's authenticatedFetch retries with a fresh id_token on this header.
    assert Plug.Conn.get_resp_header(conn, "x-shopify-retry-invalid-session-request") == ["1"]
  end

  test "builds the session for a valid Bearer token" do
    Shopifex.Shops.create_shop(%{url: @shop, scope: "orders", access_token: "t"})
    token = Shopifex.Fixtures.valid_session_token(@shop)

    conn =
      api_conn()
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      |> ShopifyApiAuth.call([])

    refute conn.halted
    assert Shopifex.Plug.current_shop(conn).url == @shop
  end
end
