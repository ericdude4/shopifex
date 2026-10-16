defmodule Shopifex.Plug.PaymentGuardTest do
  use ShopifexWeb.ConnCase

  setup do
    conn = build_conn(:get, "/premium-route?foo=bar&fizz=buzz")
    {:ok, conn: conn}
  end

  setup [:shop_in_session]

  test "payment guard blocks pay-walled function and redirects to payment page with session token",
       %{
         conn: conn
       } do
    halted_conn = Shopifex.Plug.PaymentGuard.call(conn, "block")

    assert html_response(halted_conn, 302) =~
             "<html><body>You are being <a href=\"/payment/show-plans?"

    [redirect_location] = Plug.Conn.get_resp_header(halted_conn, "location")

    conn_follow_redirect = get(Phoenix.ConnTest.build_conn(), redirect_location)

    assert Shopifex.Plug.session_token(conn_follow_redirect)
    assert html_response(conn_follow_redirect, 200) =~ "Payment options"
  end

  test "redirect stays authenticated for an HMAC-only session (no App Bridge id_token)", %{
    shop: shop
  } do
    # A legacy / non-embedded request authenticated by the signed query carries
    # no id_token to forward, so the guard attaches a short-lived token bound to
    # the plans path, which the show-plans route's :shopify_session accepts.
    conn =
      build_conn(:get, "/premium-route?foo=bar")
      |> Shopifex.Plug.build_session(shop, nil, "en")

    refute Shopifex.Plug.session_token(conn)

    halted_conn = Shopifex.Plug.PaymentGuard.call(conn, "block")
    [redirect_location] = Plug.Conn.get_resp_header(halted_conn, "location")

    query = redirect_location |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert is_binary(query["redirect_token"])
    refute Map.has_key?(query, "token")
    # Not a Shopify-style session HMAC: nothing here is accepted by other routes.
    refute Map.has_key?(query, "hmac")

    followed = get(Phoenix.ConnTest.build_conn(), redirect_location)

    assert html_response(followed, 200) =~ "Payment options"
    assert Shopifex.Plug.current_shop(followed).url == shop.url
  end

  test "a tampered redirect token is rejected", %{shop: shop} do
    [redirect_location] =
      build_conn(:get, "/premium-route")
      |> Shopifex.Plug.build_session(shop, nil, "en")
      |> Shopifex.Plug.PaymentGuard.call("block")
      |> Plug.Conn.get_resp_header("location")

    %URI{path: path, query: query} = URI.parse(redirect_location)
    params = URI.decode_query(query)
    token = params["redirect_token"]
    tampered = Map.put(params, "redirect_token", String.reverse(token))

    followed = get(Phoenix.ConnTest.build_conn(), path <> "?" <> URI.encode_query(tampered))

    refute html_response(followed, 200) =~ "Payment options"
    assert Shopifex.Plug.current_shop(followed) == nil
  end

  test "the redirect token authenticates only the plans path, so a captured link cannot be replayed elsewhere",
       %{shop: shop} do
    [redirect_location] =
      build_conn(:get, "/premium-route")
      |> Shopifex.Plug.build_session(shop, nil, "en")
      |> Shopifex.Plug.PaymentGuard.call("block")
      |> Plug.Conn.get_resp_header("location")

    %URI{query: query} = URI.parse(redirect_location)
    token = URI.decode_query(query)["redirect_token"]

    # Same token, a different :shopify_session route: no session is built, so no
    # guard downstream can mint a fresh credential from it.
    elsewhere =
      get(Phoenix.ConnTest.build_conn(), "/?" <> URI.encode_query(%{"redirect_token" => token}))

    assert Shopifex.Plug.current_shop(elsewhere) == nil
  end

  test "show-plans escapes a malicious redirect_after (no inline-script breakout)", %{conn: conn} do
    payload = "</script><script>window.__xss=1</script>"

    conn =
      get(
        conn,
        "/payment/show-plans?guard_identifier=block&redirect_after=" <>
          URI.encode_www_form(payload)
      )

    body = html_response(conn, 200)
    # The raw </script><script> breakout must NOT appear...
    refute body =~ "<script>window.__xss"
    refute body =~ "</script><script>"
    # ...because `<` is emitted as the HTML-safe JSON escape <.
    assert body =~ "\\u003Cscript"
  end

  test "payment guard grants access pay-walled function and places guard payment in private", %{
    conn: conn,
    shop: shop
  } do
    Shopifex.Shops.create_grant(%{shop_id: shop.id, grants: ["premium_access"]})

    conn = Shopifex.Plug.PaymentGuard.call(conn, "premium_access")

    assert %ShopifexDummy.Shops.Grant{grants: ["premium_access"]} = conn.private.grant_for_guard
  end

  test "redirects to show-plans when grant usages are exhausted (0 remaining)", %{
    conn: conn,
    shop: shop
  } do
    Shopifex.Shops.create_grant(%{
      shop_id: shop.id,
      grants: ["exhausted_access"],
      remaining_usages: 0,
      total_usages: 10
    })

    halted_conn = Shopifex.Plug.PaymentGuard.call(conn, "exhausted_access")

    assert halted_conn.halted
    assert html_response(halted_conn, 302) =~ "/payment/show-plans?"
  end

  test "renders show-plans with exactly one doctype even when root layout is configured", %{
    conn: conn
  } do
    defmodule DummyRoot do
      use Phoenix.Component

      def root(assigns) do
        ~H"""
        <!DOCTYPE html>
        <html>
          <body>{@inner_content}</body>
        </html>
        """
      end
    end

    conn =
      conn
      |> Phoenix.Controller.put_root_layout(html: {DummyRoot, :root})
      |> get("/payment/show-plans?guard_identifier=block&redirect_after=/")

    body = html_response(conn, 200)
    assert length(Regex.scan(~r/<!DOCTYPE html>/i, body)) == 1
  end
end
