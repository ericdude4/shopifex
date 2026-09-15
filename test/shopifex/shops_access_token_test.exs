defmodule Shopifex.ShopsAccessTokenTest do
  use Shopifex.DataCase, async: false

  alias Shopifex.Shops
  alias ShopifexDummy.OAuthHTTPClient

  @shop_url "shopifex-refresh.myshopify.com"

  setup do
    OAuthHTTPClient.reset()
    on_exit(fn -> OAuthHTTPClient.reset() end)
    :ok
  end

  defp create_shop(attrs) do
    Shops.create_shop(
      Map.merge(
        %{url: @shop_url, scope: "orders", access_token: "shpat_current"},
        attrs
      )
    )
  end

  defp in_seconds(seconds),
    do: DateTime.utc_now() |> DateTime.add(seconds, :second) |> DateTime.truncate(:second)

  defp refreshed_response(access_token \\ "shpat_refreshed") do
    {:ok,
     %{
       status_code: 200,
       body:
         Jason.encode!(%{
           access_token: access_token,
           scope: "orders",
           expires_in: 3600,
           refresh_token: "shprt_rotated",
           refresh_token_expires_in: 7_776_000
         })
     }}
  end

  describe "expiry predicates" do
    test "non-expiring tokens never expire" do
      shop = create_shop(%{})

      refute Shops.expiring_access_token?(shop)
      refute Shops.access_token_expiring?(shop)
      refute Shops.access_token_expired?(shop)
      assert Shops.refresh_token_expired?(shop)
    end

    test "expiring tokens expire within the refresh margin" do
      shop =
        create_shop(%{
          refresh_token: "shprt_current",
          access_token_expires_at: in_seconds(120),
          refresh_token_expires_at: in_seconds(7_776_000)
        })

      assert Shops.expiring_access_token?(shop)
      assert Shops.access_token_expiring?(shop)
      refute Shops.access_token_expired?(shop)
      refute Shops.refresh_token_expired?(shop)
    end

    test "refresh tokens past their expiry are expired" do
      shop =
        create_shop(%{
          refresh_token: "shprt_current",
          access_token_expires_at: in_seconds(3600),
          refresh_token_expires_at: in_seconds(-1)
        })

      assert Shops.refresh_token_expired?(shop)
    end
  end

  describe "get_access_token/1" do
    test "returns the stored token when it is not close to expiry" do
      shop =
        create_shop(%{
          refresh_token: "shprt_current",
          access_token_expires_at: in_seconds(3600),
          refresh_token_expires_at: in_seconds(7_776_000)
        })

      assert {:ok, "shpat_current"} = Shops.get_access_token(shop)
      assert OAuthHTTPClient.requests() == []
    end

    test "returns non-expiring tokens untouched" do
      shop = create_shop(%{})
      assert {:ok, "shpat_current"} = Shops.get_access_token(shop)
      assert "shpat_current" = Shops.get_access_token!(shop)
    end

    test "refreshes and persists the new token pair when the token is expiring" do
      shop =
        create_shop(%{
          refresh_token: "shprt_current",
          access_token_expires_at: in_seconds(60),
          refresh_token_expires_at: in_seconds(7_776_000)
        })

      OAuthHTTPClient.expect(refreshed_response())

      assert {:ok, "shpat_refreshed"} = Shops.get_access_token(shop)

      assert [%{body: %{"grant_type" => "refresh_token", "refresh_token" => "shprt_current"}}] =
               OAuthHTTPClient.requests()

      persisted = Shops.get_shop_by_url(@shop_url)
      assert persisted.access_token == "shpat_refreshed"
      assert persisted.refresh_token == "shprt_rotated"
      assert DateTime.compare(persisted.access_token_expires_at, in_seconds(3000)) == :gt
      assert DateTime.compare(persisted.refresh_token_expires_at, in_seconds(7_000_000)) == :gt
    end

    test "reuses a refresh performed by another process instead of refreshing again" do
      shop =
        create_shop(%{
          refresh_token: "shprt_current",
          access_token_expires_at: in_seconds(60),
          refresh_token_expires_at: in_seconds(7_776_000)
        })

      # Simulate another node rotating the token before we acquire the lock
      Shops.update_shop(shop, %{
        access_token: "shpat_from_other_node",
        refresh_token: "shprt_from_other_node",
        access_token_expires_at: in_seconds(3600)
      })

      assert {:ok, "shpat_from_other_node"} = Shops.get_access_token(shop)
      assert OAuthHTTPClient.requests() == []
    end

    test "clears the refresh token when Shopify rejects it" do
      shop =
        create_shop(%{
          refresh_token: "shprt_dead",
          access_token_expires_at: in_seconds(-10),
          refresh_token_expires_at: in_seconds(7_776_000)
        })

      OAuthHTTPClient.expect(
        {:ok, %{status_code: 400, body: Jason.encode!(%{error: "invalid_grant"})}}
      )

      assert {:error, :invalid_grant} = Shops.get_access_token(shop)
      assert is_nil(Shops.get_shop_by_url(@shop_url).refresh_token)

      # Subsequent calls fail fast without hitting Shopify again
      assert {:error, :refresh_token_expired} = Shops.get_access_token(Shops.reload_shop(shop))
      assert length(OAuthHTTPClient.requests()) == 1

      assert_raise Shopifex.AccessTokenError, ~r/shopifex-refresh.myshopify.com/, fn ->
        Shops.get_access_token!(Shops.reload_shop(shop))
      end
    end

    test "keeps the refresh token on transient errors" do
      shop =
        create_shop(%{
          refresh_token: "shprt_current",
          access_token_expires_at: in_seconds(-10),
          refresh_token_expires_at: in_seconds(7_776_000)
        })

      OAuthHTTPClient.expect({:error, :timeout})

      assert {:error, :http_error} = Shops.get_access_token(shop)
      assert Shops.get_shop_by_url(@shop_url).refresh_token == "shprt_current"
    end

    test "serializes concurrent refreshes so only one request is made" do
      shop =
        create_shop(%{
          refresh_token: "shprt_current",
          access_token_expires_at: in_seconds(-10),
          refresh_token_expires_at: in_seconds(7_776_000)
        })

      parent = self()

      tasks =
        for _ <- 1..5 do
          Task.async(fn ->
            Ecto.Adapters.SQL.Sandbox.allow(ShopifexDummy.Repo, parent, self())

            OAuthHTTPClient.expect(fn _url, _body, _headers ->
              # Slow the request down so the other tasks queue on the lock
              Process.sleep(50)
              send(parent, :refreshed)
              refreshed_response()
            end)

            Shops.get_access_token(shop)
          end)
        end

      results = Task.await_many(tasks, 5_000)
      assert Enum.all?(results, &(&1 == {:ok, "shpat_refreshed"}))

      assert_received :refreshed
      refute_received :refreshed
    end
  end
end
