defmodule Shopifex.Plug.PaymentGuardTest do
  use ShopifexWeb.ConnCase

  setup do
    conn = build_conn(:get, "/premium-route?foo=bar&fizz=buzz")
    {:ok, conn: conn}
  end

  setup [:shop_in_session]

  test "payment guard blocks pay-walled function and redirects to payment page with session token", %{
    conn: conn
  } do
    halted_conn = Shopifex.Plug.PaymentGuard.call(conn, "block")

    assert html_response(halted_conn, 302) =~
             "<html><body>You are being <a href=\"/payment/show-plans?guard_identifier=block"

    [redirect_location] = Plug.Conn.get_resp_header(halted_conn, "location")

    conn_follow_redirect = get(Phoenix.ConnTest.build_conn(), redirect_location)

    assert Shopifex.Plug.session_token(conn_follow_redirect)
    assert html_response(conn_follow_redirect, 200) =~ "Components.WrappedShowPlans"
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
