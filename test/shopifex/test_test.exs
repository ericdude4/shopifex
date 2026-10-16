defmodule Shopifex.TestTest do
  use Shopifex.DataCase, async: false

  import Shopifex.Test

  alias Shopifex.Shops
  alias Shopifex.SessionToken
  alias Shopifex.Plug.{ShopifyApiAuth, ShopifyWebhook, ValidateHmac}

  @shop "helpers.myshopify.com"

  defp shop, do: Shops.create_shop(%{url: @shop, scope: "orders", access_token: "x"})

  test "sign_session_token/2 produces a token SessionToken.verify accepts" do
    assert {:ok, claims} = SessionToken.verify(sign_session_token(@shop), @shop)
    assert claims["dest"] == "https://#{@shop}"
    assert claims["sub"] == "1"
  end

  test "put_shopify_session/3 loads current_shop and attaches a Bearer token the API plug accepts" do
    shop = shop()

    conn =
      Plug.Test.conn(:get, "/")
      |> Plug.Conn.fetch_query_params()
      |> put_shopify_session(shop)

    assert Shopifex.Plug.current_shop(conn).url == @shop
    refute ShopifyApiAuth.call(conn, []).halted
  end

  test "sign_webhook/2 + put_webhook_hmac/3 pass the webhook plug" do
    shop()
    raw = ~s({"id": 1})

    conn =
      Plug.Test.conn(:post, "/webhook")
      |> Plug.Conn.put_req_header("x-shopify-shop-domain", @shop)
      |> put_webhook_hmac(raw)

    refute ShopifyWebhook.call(conn, []).halted
  end

  test "sign_query_hmac/2 passes ValidateHmac" do
    params = %{"shop" => @shop, "timestamp" => to_string(System.system_time(:second))}
    full = Map.put(params, "hmac", sign_query_hmac(params))
    conn = %{Plug.Test.conn(:get, "/") | params: full, query_params: full}

    refute ValidateHmac.call(conn, []).halted
  end

  test "sign_query_hmac/1 matches an independently computed HMAC digest" do
    params = %{"shop" => @shop, "timestamp" => to_string(System.system_time(:second))}
    secret = Application.fetch_env!(:shopifex, :secret)

    query_string =
      params
      |> Enum.sort()
      |> Enum.map_join("&", fn {k, v} -> "#{k}=#{v}" end)

    expected =
      :crypto.mac(:hmac, :sha256, secret, query_string)
      |> Base.encode16(case: :lower)

    assert sign_query_hmac(params) == expected
  end

  test "sign_query_hmac/2 handles the `ids` bulk-action quirk (round-trips through ValidateHmac)" do
    params = %{
      "ids" => ["1", "2"],
      "shop" => @shop,
      "timestamp" => to_string(System.system_time(:second))
    }

    full = Map.put(params, "hmac", sign_query_hmac(params))
    conn = %{Plug.Test.conn(:get, "/") | params: full, query_params: full}

    refute ValidateHmac.call(conn, []).halted
  end
end
