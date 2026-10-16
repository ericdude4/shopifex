defmodule Shopifex.PlugTest do
  use ShopifexWeb.ConnCase
  alias ShopifexDummy.Shop

  setup [:shop_in_session]

  test "put_shop_in_session/2 puts shop in shopifex conn.private", %{conn: conn} do
    shop =
      conn
      |> Shopifex.Plug.current_shop()
      |> Map.put(:url, "FOO BAR")

    conn = Shopifex.Plug.put_shop_in_session(conn, shop)

    assert %Shop{url: "FOO BAR"} = Shopifex.Plug.current_shop(conn)
  end

  describe "build_hmac/1" do
    test "GET request build hash with signature query param" do
      assert "3cf1f3876199f1b4254ff0f6a2d1e867e8ea5c0555ccff923c74547ae4da414b" =
               Shopifex.Plug.build_hmac(%Plug.Conn{
                 method: "GET",
                 query_params: %{
                   "logged_in_customer_id" => "",
                   "path_prefix" => "/apps/fw-cart-redirect-page",
                   "shop" => "shopifex.myshopify.com",
                   "signature" =>
                     "5056c56d0cfa96fc37683faa5653af2ff5412ea4dd5233db139367010999f6b5",
                   "timestamp" => "1667857512"
                 }
               })
    end

    test "GET request build hash with hmac query param" do
      assert "40c54cad699dcd6fc5a2e27b067a652ebb5f011faa4f061b9de5e8ba3c6384c8" =
               Shopifex.Plug.build_hmac(%Plug.Conn{
                 method: "GET",
                 query_params: %{
                   "hmac" => "foobar",
                   "logged_in_customer_id" => "",
                   "path_prefix" => "/apps/fw-cart-redirect-page",
                   "shop" => "shopifex.myshopify.com",
                   "signature" => "a signature to ensure that hmac takes precedence",
                   "timestamp" => "1667857512"
                 }
               })
    end

    test "GET request build hash for list of ids with hmac query param" do
      assert "ac63a0487ee1ea0a1ea46ac4d2aa59c6c34c8be2c86445c8c13c420141ed8bfd" =
               Shopifex.Plug.build_hmac(%Plug.Conn{
                 method: "GET",
                 query_params: %{
                   "hmac" => "foobar",
                   "logged_in_customer_id" => "",
                   "path_prefix" => "/apps/fw-cart-redirect-page",
                   "shop" => "shopifex.myshopify.com",
                   "ids" => ["1234", "5678"],
                   "signature" => "a signature to ensure that hmac takes precedence",
                   "timestamp" => "1667857512"
                 }
               })
    end

    test "POST request build hash with assigned raw_body (Base64, case-preserved)" do
      assert "yJgOX9Rf6sY058r98V06ZCrhbw7TlcryRf12e7RmKoU=" =
               %Plug.Conn{method: "POST"}
               |> Plug.Conn.assign(:raw_body, "{\"foo\": \"bar\"}")
               |> Shopifex.Plug.build_hmac()
    end

    test "POST with signature query param" do
      assert "3cf1f3876199f1b4254ff0f6a2d1e867e8ea5c0555ccff923c74547ae4da414b" =
               Shopifex.Plug.build_hmac(%Plug.Conn{
                 method: "POST",
                 query_params: %{
                   "logged_in_customer_id" => "",
                   "path_prefix" => "/apps/fw-cart-redirect-page",
                   "shop" => "shopifex.myshopify.com",
                   "signature" =>
                     "5056c56d0cfa96fc37683faa5653af2ff5412ea4dd5233db139367010999f6b5",
                   "timestamp" => "1667857512"
                 }
               })
    end
  end

  describe "validate_timestamp/2" do
    test "accepts a bare Plug.Test.conn whose query params were never fetched" do
      conn = Plug.Test.conn(:get, "/?timestamp=#{System.system_time(:second)}")

      assert Shopifex.Plug.validate_timestamp(conn) == :ok
    end
  end

  describe "get_hmac/1" do
    test "GET request gets hash from hmac param" do
      assert "foobar" =
               Shopifex.Plug.get_hmac(%Plug.Conn{
                 method: "GET",
                 params: %{
                   "hmac" => "foobar",
                   "signature" => "a signature to ensure that hmac takes precedence",
                   "timestamp" => "1667857512"
                 }
               })
    end

    test "GET request gets hash from signature param" do
      assert "foo signature" =
               Shopifex.Plug.get_hmac(%Plug.Conn{
                 method: "GET",
                 params: %{
                   "signature" => "foo signature",
                   "timestamp" => "1667857512"
                 }
               })
    end

    test "POST request gets Base64 hash from header verbatim (case-preserved)" do
      assert "yJgOX9Rf6sY058r98V06ZCrhbw7TlcryRf12e7RmKoU=" =
               %Plug.Conn{method: "POST"}
               |> Plug.Conn.put_req_header(
                 "x-shopify-hmac-sha256",
                 "yJgOX9Rf6sY058r98V06ZCrhbw7TlcryRf12e7RmKoU="
               )
               |> Shopifex.Plug.get_hmac()
    end
  end

  describe "sign_redirect/3 and verify_redirect/2" do
    @salt "shopifex signed redirect"
    @shop_url "redirect.myshopify.com"
    @plans_path "/payment/show-plans"
    @select_path "/payment/select-plan"

    defp secret, do: Application.fetch_env!(:shopifex, :secret)

    test "round-trips the shop url at the signed path" do
      token = Shopifex.Plug.sign_redirect(@shop_url, @plans_path)

      assert Shopifex.Plug.verify_redirect(token, @plans_path) == {:ok, @shop_url}
    end

    test "rejects the token at any other path" do
      token = Shopifex.Plug.sign_redirect(@shop_url, @plans_path)

      assert Shopifex.Plug.verify_redirect(token, @select_path) == :error
      assert Shopifex.Plug.verify_redirect(token, "/") == :error
      assert Shopifex.Plug.verify_redirect(token, @plans_path <> "/") == :error
    end

    test "rejects a tampered or non-binary token" do
      token = Shopifex.Plug.sign_redirect(@shop_url, @plans_path)

      assert Shopifex.Plug.verify_redirect(String.reverse(token), @plans_path) == :error
      assert Shopifex.Plug.verify_redirect(nil, @plans_path) == :error
      assert Shopifex.Plug.verify_redirect(%{}, @plans_path) == :error
    end

    test "honours :max_age — a token signed with max_age: 0 is already expired" do
      token = Shopifex.Plug.sign_redirect(@shop_url, @select_path, max_age: 0)

      assert Shopifex.Plug.verify_redirect(token, @select_path) == :error
    end

    test "honours the signer's :max_age instead of the 90 s default" do
      now = System.system_time(:second)

      # Signed two minutes ago with a one-hour lifetime: stale under the old
      # fixed 90 s window, valid under the lifetime the signer embedded.
      token =
        Plug.Crypto.sign(
          secret(),
          @salt,
          %{shop_url: @shop_url, path: @select_path, exp: now + 3600 - 120},
          signed_at: now - 120,
          max_age: 3600
        )

      assert Shopifex.Plug.verify_redirect(token, @select_path) == {:ok, @shop_url}
    end

    test "rejects a token whose exp claim has passed even if Plug.Crypto's max age has not" do
      now = System.system_time(:second)

      token =
        Plug.Crypto.sign(
          secret(),
          @salt,
          %{shop_url: @shop_url, path: @select_path, exp: now - 1},
          max_age: 3600
        )

      assert Shopifex.Plug.verify_redirect(token, @select_path) == :error
    end

    test "rejects a legacy-format token that carries no exp claim" do
      # The payload shape sign_redirect/2 produced before :max_age existed.
      legacy = Plug.Crypto.sign(secret(), @salt, %{shop_url: @shop_url, path: @plans_path})

      assert Shopifex.Plug.verify_redirect(legacy, @plans_path) == :error
    end

    test "accepts a token signed with the rotated :old_secret" do
      Application.put_env(:shopifex, :old_secret, "shpss_previous_secret")
      on_exit(fn -> Application.delete_env(:shopifex, :old_secret) end)

      now = System.system_time(:second)

      token =
        Plug.Crypto.sign(
          "shpss_previous_secret",
          @salt,
          %{shop_url: @shop_url, path: @plans_path, exp: now + 90},
          max_age: 90
        )

      assert Shopifex.Plug.verify_redirect(token, @plans_path) == {:ok, @shop_url}
    end

    test "the PaymentGuard redirect token still verifies at the plans path only", %{shop: shop} do
      [location] =
        build_conn(:get, "/premium-route")
        |> Shopifex.Plug.build_session(shop, nil, "en")
        |> Shopifex.Plug.PaymentGuard.call("block")
        |> Plug.Conn.get_resp_header("location")

      %URI{path: @plans_path, query: query} = URI.parse(location)
      token = URI.decode_query(query)["redirect_token"]

      assert Shopifex.Plug.verify_redirect(token, @plans_path) == {:ok, shop.url}
      assert Shopifex.Plug.verify_redirect(token, @select_path) == :error
    end
  end
end
