defmodule Shopifex.Plug.PaymentGuardTest do
  use ExUnit.Case, async: true
  use Plug.Test

  defmodule PaymentGuard do
    use Shopifex.PaymentGuard

    def payment_for_guard(_shop, "grant"), do: %{}
    def payment_for_guard(_shop, "block"), do: nil
  end

  setup do
    shop = %{url: "shopifex.myshopify.com", scope: "orders", access_token: "asdf1234"}

    {:ok, shop: shop}
  end

  test "payment guard blocks pay-walled function and redirects to payment route", %{shop: shop} do
    conn =
      conn(:get, "/premium-route?foo=bar&fizz=buzz", %{})
      |> Plug.Conn.put_private(:shop, shop)
      |> Shopifex.Plug.PaymentGuard.call("block")

    assert conn.status == 302

    assert Plug.Conn.get_resp_header(conn, "location") == [
             "/payment?guard=block&redirect_after=%2Fpremium-route%3Ffoo%3Dbar%26fizz%3Dbuzz"
           ]
  end

  test "payment guard grants access pay-walled function and places guard payment in session", %{
    shop: shop
  } do
    conn =
      conn(:get, "/premium-route?foo=bar&fizz=buzz", %{})
      |> Plug.Conn.put_private(:shop, shop)
      |> Shopifex.Plug.PaymentGuard.call("grant")

    assert conn.private.payment_for_guard == %{}
  end
end
