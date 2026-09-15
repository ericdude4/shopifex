defmodule Shopifex.Plug.EnsureAccessTokenTest do
  use ShopifexWeb.ConnCase

  alias Shopifex.Shops
  alias ShopifexDummy.OAuthHTTPClient

  setup do
    OAuthHTTPClient.reset()
    previous = Application.get_env(:shopifex, :expiring_offline_access_tokens)
    Application.put_env(:shopifex, :expiring_offline_access_tokens, true)

    on_exit(fn ->
      OAuthHTTPClient.reset()
      Application.put_env(:shopifex, :expiring_offline_access_tokens, previous)
    end)

    conn = build_conn(:get, "/my-route?foo=bar")
    {:ok, conn: conn}
  end

  setup [:shop_in_session]

  defp in_seconds(seconds),
    do: DateTime.utc_now() |> DateTime.add(seconds, :second) |> DateTime.truncate(:second)

  defp session_token(shop_url) do
    {:ok, token, _claims} =
      Shopifex.Guardian.encode_and_sign(%{url: shop_url}, %{"dest" => "https://#{shop_url}"})

    token
  end

  test "is a no-op when expiring tokens are disabled", %{conn: conn} do
    Application.put_env(:shopifex, :expiring_offline_access_tokens, false)

    conn = Shopifex.Plug.EnsureAccessToken.call(conn, [])
    refute conn.halted
  end

  test "passes shops which already hold a refresh token", %{conn: conn, shop: shop} do
    shop =
      Shops.update_shop(shop, %{
        refresh_token: "shprt_current",
        access_token_expires_at: in_seconds(3600),
        refresh_token_expires_at: in_seconds(7_776_000)
      })

    conn =
      conn
      |> Shopifex.Plug.put_shop_in_session(shop)
      |> Shopifex.Plug.EnsureAccessToken.call([])

    refute conn.halted
    assert OAuthHTTPClient.requests() == []
  end

  test "exchanges the id_token param for an expiring token without redirecting", %{
    conn: conn,
    shop: shop
  } do
    OAuthHTTPClient.expect(
      {:ok,
       %{
         status_code: 200,
         body:
           Jason.encode!(%{
             access_token: "shpat_exchanged",
             scope: "orders",
             expires_in: 3600,
             refresh_token: "shprt_exchanged",
             refresh_token_expires_in: 7_776_000
           })
       }}
    )

    id_token = session_token(shop.url)

    conn =
      conn
      |> Map.put(:params, %{"id_token" => id_token})
      |> Shopifex.Plug.EnsureAccessToken.call([])

    refute conn.halted

    assert [%{body: %{"grant_type" => "urn:ietf:params:oauth:grant-type:token-exchange"} = body}] =
             OAuthHTTPClient.requests()

    assert body["subject_token"] == id_token

    assert %{access_token: "shpat_exchanged", refresh_token: "shprt_exchanged"} =
             Shopifex.Plug.current_shop(conn)

    assert Shops.get_shop_by_url(shop.url).refresh_token == "shprt_exchanged"
  end

  test "ignores Shopifex session tokens which are not Shopify id tokens", %{
    conn: conn,
    shop: shop
  } do
    {:ok, token, _} = Shopifex.Guardian.encode_and_sign(shop)

    conn =
      conn
      |> Map.put(:params, %{"token" => token})
      |> Shopifex.Plug.EnsureAccessToken.call([])

    assert conn.halted
    assert OAuthHTTPClient.requests() == []
  end

  test "redirects to the OAuth update flow when no session token is available", %{conn: conn} do
    conn = Shopifex.Plug.EnsureAccessToken.call(conn, [])

    assert conn.halted
    assert html_response(conn, 200) =~ "WrappedRedirect"

    assert conn.assigns.redirect_location =~
             "https://shopifex.myshopify.com/admin/oauth/authorize?client_id=thisisafakeapikey"

    assert conn.assigns.redirect_location =~ "auth%2Fupdate"
  end

  test "falls back to the OAuth update flow when token exchange is rejected", %{
    conn: conn,
    shop: shop
  } do
    OAuthHTTPClient.expect(
      {:ok, %{status_code: 400, body: ~s({"error":"invalid_subject_token"})}}
    )

    conn =
      conn
      |> Map.put(:params, %{"id_token" => session_token(shop.url)})
      |> Shopifex.Plug.EnsureAccessToken.call([])

    assert conn.halted
    assert conn.assigns.redirect_location =~ "/admin/oauth/authorize"
  end

  test "throws error when shop not in session", %{conn: conn} do
    assert_raise Shopifex.RuntimeError, fn ->
      conn
      |> Map.put(:private, %{})
      |> Shopifex.Plug.EnsureAccessToken.call([])
    end
  end
end
