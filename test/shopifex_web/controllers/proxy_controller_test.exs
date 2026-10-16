defmodule ShopifexDummyWeb.ProxyControllerTest do
  @moduledoc """
  End-to-end coverage of the `:shopify_proxy` pipeline (ValidateHmac +
  LoadProxyShop): a validly-signed app-proxy request resolves `current_shop`,
  a tampered signature is rejected, and an unknown shop passes through.
  """
  use ShopifexWeb.ConnCase, async: false

  import Shopifex.Test

  alias Shopifex.Shops

  setup do
    shop = Shops.create_shop(%{url: "proxy.myshopify.com", scope: "orders", access_token: "t"})
    {:ok, shop: shop}
  end

  # App-proxy requests are signed over the params (sorted, empty joiner) and carry
  # the digest in a `signature` param — distinct from the admin `hmac`.
  defp signed_path(params) do
    signature = sign_query_hmac(params, joiner: "")
    "/proxy?" <> URI.encode_query(Map.put(params, "signature", signature))
  end

  test "a validly-signed request loads current_shop through the pipeline", %{
    conn: conn,
    shop: shop
  } do
    params = %{"shop" => shop.url, "timestamp" => to_string(System.system_time(:second))}

    conn = get(conn, signed_path(params))

    assert response(conn, 200) =~ "shop: #{shop.url}"
  end

  test "a tampered signature is rejected with 401", %{conn: conn, shop: shop} do
    params = %{"shop" => shop.url, "timestamp" => to_string(System.system_time(:second))}
    path = "/proxy?" <> URI.encode_query(Map.put(params, "signature", "deadbeef"))

    conn = get(conn, path)

    assert conn.status == 401
  end

  test "a validly-signed request for an unknown shop passes through (current_shop nil)", %{
    conn: conn
  } do
    params = %{
      "shop" => "ghost.myshopify.com",
      "timestamp" => to_string(System.system_time(:second))
    }

    conn = get(conn, signed_path(params))

    assert response(conn, 200) =~ "no shop"
  end

  test "a map-valued timestamp is rejected with 401, never a raised 500", %{
    conn: conn,
    shop: shop
  } do
    conn = get(conn, "/proxy?shop=#{shop.url}&timestamp[x]=y&signature=deadbeef")

    assert response(conn, 401)
  end

  test "a map-valued param next to a signature is rejected with 401", %{conn: conn, shop: shop} do
    fresh = System.system_time(:second)
    conn = get(conn, "/proxy?shop=#{shop.url}&timestamp=#{fresh}&foo[x]=y&signature=deadbeef")

    assert response(conn, 401)
  end
end
