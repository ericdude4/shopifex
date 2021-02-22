defmodule Shopifex.Plug.PaymentGuardTest do
  use ShopifexWeb.ConnCase

  setup do
    conn = build_conn(:get, "/premium-route?foo=bar&fizz=buzz")
    {:ok, conn: conn}
  end

  setup [:shop_in_session]

  test "payment guard blocks pay-walled function and redirects to payment route", %{
    conn: conn
  } do
    conn = Shopifex.Plug.PaymentGuard.call(conn, "block")

    assert conn.status == 302

    assert Plug.Conn.get_resp_header(conn, "location") == [
             "/payment/show-plans?guard=block&redirect_after=%2Fpremium-route%3Ffoo%3Dbar%26fizz%3Dbuzz"
           ]
  end

  test "payment guard grants access pay-walled function and places guard payment in session", %{
    conn: conn,
    shop: shop
  } do
    Shopifex.Shops.create_grant(%{shop: shop, grants: ["premium_access"]})

    conn = Shopifex.Plug.PaymentGuard.call(conn, "premium_access")

    assert %ShopifexDummy.Shops.Grant{grants: ["premium_access"]} = conn.private.grant_for_guard
  end
end
