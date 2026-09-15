defmodule Shopifex.OAuthTest do
  use ExUnit.Case, async: false

  alias Shopifex.OAuth
  alias ShopifexDummy.OAuthHTTPClient

  @shop_url "shopifex.myshopify.com"
  @token_endpoint "https://shopifex.myshopify.com/admin/oauth/access_token"

  setup do
    OAuthHTTPClient.reset()
    previous = Application.get_env(:shopifex, :expiring_offline_access_tokens)

    on_exit(fn ->
      OAuthHTTPClient.reset()
      Application.put_env(:shopifex, :expiring_offline_access_tokens, previous)
    end)

    :ok
  end

  defp expiring_response() do
    {:ok,
     %{
       status_code: 200,
       body:
         Jason.encode!(%{
           access_token: "shpat_new",
           scope: "orders",
           expires_in: 3600,
           refresh_token: "shprt_new",
           refresh_token_expires_in: 7_776_000
         })
     }}
  end

  describe "token_params/2" do
    test "converts expires_in values into absolute datetimes" do
      now = ~U[2026-09-14 12:00:00Z]

      assert %{
               access_token: "shpat_new",
               scope: "orders",
               refresh_token: "shprt_new",
               access_token_expires_at: ~U[2026-09-14 13:00:00Z],
               refresh_token_expires_at: ~U[2026-12-13 12:00:00Z]
             } =
               OAuth.token_params(
                 %{
                   "access_token" => "shpat_new",
                   "scope" => "orders",
                   "expires_in" => 3600,
                   "refresh_token" => "shprt_new",
                   "refresh_token_expires_in" => 7_776_000
                 },
                 now
               )
    end

    test "leaves expiry fields nil for non-expiring tokens" do
      assert %{
               access_token: "shpat_forever",
               refresh_token: nil,
               access_token_expires_at: nil,
               refresh_token_expires_at: nil
             } = OAuth.token_params(%{access_token: "shpat_forever", scope: "orders"})
    end
  end

  describe "request_access_token/2" do
    test "requests a non-expiring token by default" do
      Application.put_env(:shopifex, :expiring_offline_access_tokens, false)

      OAuthHTTPClient.expect(
        {:ok,
         %{status_code: 200, body: Jason.encode!(%{access_token: "shpat_x", scope: "orders"})}}
      )

      assert {:ok, %{access_token: "shpat_x", refresh_token: nil}} =
               OAuth.request_access_token(@shop_url, "auth-code")

      assert [%{url: @token_endpoint, body: body}] = OAuthHTTPClient.requests()

      assert body == %{
               "client_id" => "thisisafakeapikey",
               "client_secret" => "shpss_thisisafakesecret",
               "code" => "auth-code"
             }
    end

    test "requests an expiring token when enabled" do
      Application.put_env(:shopifex, :expiring_offline_access_tokens, true)
      OAuthHTTPClient.expect(expiring_response())

      assert {:ok, %{access_token: "shpat_new", refresh_token: "shprt_new"} = params} =
               OAuth.request_access_token(@shop_url, "auth-code")

      assert %DateTime{} = params.access_token_expires_at
      assert %DateTime{} = params.refresh_token_expires_at

      assert [%{body: %{"expiring" => 1, "code" => "auth-code"}}] = OAuthHTTPClient.requests()
    end

    test "classifies 4xx responses as invalid grants" do
      OAuthHTTPClient.expect(
        {:ok, %{status_code: 400, body: Jason.encode!(%{error: "invalid_request"})}}
      )

      assert {:error, :invalid_grant, %{"error" => "invalid_request"}} =
               OAuth.request_access_token(@shop_url, "bad-code")
    end

    test "classifies 5xx responses and transport errors" do
      OAuthHTTPClient.expect({:ok, %{status_code: 502, body: "bad gateway"}})

      assert {:error, :unexpected_response, "bad gateway"} =
               OAuth.request_access_token(@shop_url, "c")

      OAuthHTTPClient.expect({:error, :timeout})
      assert {:error, :http_error, :timeout} = OAuth.request_access_token(@shop_url, "c")
    end
  end

  describe "refresh_access_token/3" do
    test "posts the refresh token grant" do
      OAuthHTTPClient.expect(expiring_response())

      assert {:ok, %{access_token: "shpat_new", refresh_token: "shprt_new"}} =
               OAuth.refresh_access_token(@shop_url, "shprt_old")

      assert [%{url: @token_endpoint, body: body}] = OAuthHTTPClient.requests()

      assert body == %{
               "client_id" => "thisisafakeapikey",
               "client_secret" => "shpss_thisisafakesecret",
               "grant_type" => "refresh_token",
               "refresh_token" => "shprt_old"
             }
    end

    test "allows the app credentials to be overridden" do
      OAuthHTTPClient.expect(expiring_response())

      assert {:ok, _} =
               OAuth.refresh_access_token(@shop_url, "shprt_old",
                 client_id: "other-app",
                 client_secret: "other-secret"
               )

      assert [%{body: %{"client_id" => "other-app", "client_secret" => "other-secret"}}] =
               OAuthHTTPClient.requests()
    end
  end

  describe "exchange_session_token/2" do
    test "posts the token exchange grant for an expiring offline token" do
      Application.put_env(:shopifex, :expiring_offline_access_tokens, true)
      OAuthHTTPClient.expect(expiring_response())

      assert {:ok, %{access_token: "shpat_new"}} =
               OAuth.exchange_session_token(@shop_url, "session-jwt")

      assert [%{body: body}] = OAuthHTTPClient.requests()

      assert body == %{
               "client_id" => "thisisafakeapikey",
               "client_secret" => "shpss_thisisafakesecret",
               "grant_type" => "urn:ietf:params:oauth:grant-type:token-exchange",
               "subject_token" => "session-jwt",
               "subject_token_type" => "urn:ietf:params:oauth:token-type:id_token",
               "requested_token_type" =>
                 "urn:shopify:params:oauth:token-type:offline-access-token",
               "expiring" => 1
             }
    end
  end

  describe "cycle_offline_access_token/3" do
    test "exchanges a non-expiring offline token for an expiring pair" do
      # Independent of the expiring_offline_access_tokens config: expiring is always 1
      Application.put_env(:shopifex, :expiring_offline_access_tokens, false)
      OAuthHTTPClient.expect(expiring_response())

      assert {:ok, %{access_token: "shpat_new", refresh_token: "shprt_new"}} =
               OAuth.cycle_offline_access_token(@shop_url, "shpat_legacy")

      assert [%{url: @token_endpoint, body: body}] = OAuthHTTPClient.requests()

      assert body == %{
               "client_id" => "thisisafakeapikey",
               "client_secret" => "shpss_thisisafakesecret",
               "grant_type" => "urn:ietf:params:oauth:grant-type:token-exchange",
               "subject_token" => "shpat_legacy",
               "subject_token_type" => "urn:shopify:params:oauth:token-type:offline-access-token",
               "requested_token_type" =>
                 "urn:shopify:params:oauth:token-type:offline-access-token",
               "expiring" => 1
             }
    end

    test "surfaces Shopify's rejection of an unsupported subject token" do
      OAuthHTTPClient.expect(
        {:ok, %{status_code: 400, body: ~s({"error":"invalid_subject_token"})}}
      )

      assert {:error, :invalid_grant, %{"error" => "invalid_subject_token"}} =
               OAuth.cycle_offline_access_token(@shop_url, "shpat_already_expiring")
    end
  end

  describe "exchange_tokens_via_session?/0" do
    test "defaults to true and only false disables it" do
      previous = Application.get_env(:shopifex, :exchange_tokens_via_session)

      on_exit(fn ->
        Application.put_env(:shopifex, :exchange_tokens_via_session, previous)
      end)

      Application.delete_env(:shopifex, :exchange_tokens_via_session)
      assert OAuth.exchange_tokens_via_session?()

      Application.put_env(:shopifex, :exchange_tokens_via_session, false)
      refute OAuth.exchange_tokens_via_session?()
    end
  end

  describe "authorize_url/3" do
    test "builds the OAuth authorize url" do
      assert OAuth.authorize_url(@shop_url, "https://shopifex-dummy.com/auth/update") ==
               "https://shopifex.myshopify.com/admin/oauth/authorize?client_id=thisisafakeapikey&scope=orders&redirect_uri=https%3A%2F%2Fshopifex-dummy.com%2Fauth%2Fupdate"
    end

    test "includes state when provided" do
      assert OAuth.authorize_url(@shop_url, "https://x.com/cb", state: "abc", scope: "read_x") =~
               "&state=abc"
    end
  end
end
