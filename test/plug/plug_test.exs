defmodule Shopifex.PlugTest do
  use ShopifexWeb.ConnCase

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

    test "POST request build hash with assigned raw_body" do
      assert "yjgox9rf6sy058r98v06zcrhbw7tlcryrf12e7rmkou=" =
               %Plug.Conn{method: "POST"}
               |> Plug.Conn.assign(:raw_body, "{\"foo\": \"bar\"}")
               |> Shopifex.Plug.build_hmac()
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

    test "POST request gets hash from signature header" do
      assert "yjgox9rf6sy058r98v06zcrhbw7tlcryrf12e7rmkou=" =
               %Plug.Conn{method: "POST"}
               |> Plug.Conn.put_req_header(
                 "x-shopify-hmac-sha256",
                 "yjgox9rf6sy058r98v06zcrhbw7tlcryrf12e7rmkou="
               )
               |> Shopifex.Plug.get_hmac()
    end
  end
end
