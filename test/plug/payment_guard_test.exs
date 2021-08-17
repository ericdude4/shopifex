defmodule Shopifex.Plug.PaymentGuardTest do
  use ShopifexWeb.ConnCase

  setup do
    conn = build_conn(:get, "/premium-route?foo=bar&fizz=buzz")
    {:ok, conn: conn}
  end

  setup [:shop_in_session]

  test "payment guard blocks pay-walled function and redirects to payment page", %{
    conn: conn
  } do
    conn = Shopifex.Plug.PaymentGuard.call(conn, "block")

    assert html_response(conn, 302) =~ "<html><body>You are being <a href=\"/payment/show-plans?guard_identifier=block"
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
