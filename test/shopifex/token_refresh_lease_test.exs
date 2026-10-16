defmodule Shopifex.TokenRefreshLeaseTest do
  use Shopifex.DataCase, async: false

  alias Shopifex.TokenRefreshLease

  test "an expired lease can be taken over" do
    Repo.insert_all("shopifex_token_refresh_leases", [
      %{
        shop_url: "expired.myshopify.com",
        owner: "dead-owner",
        lease_expires_at: DateTime.add(DateTime.utc_now(), -1, :second)
      }
    ])

    assert {:ok, owner} = TokenRefreshLease.acquire("expired.myshopify.com")
    refute owner == "dead-owner"

    assert %{owner: ^owner} =
             Repo.one(
               from(lease in "shopifex_token_refresh_leases",
                 where: lease.shop_url == "expired.myshopify.com",
                 select: %{owner: lease.owner}
               )
             )
  end

  test "a stale owner cannot release its successor's lease" do
    assert {:ok, stale_owner} = TokenRefreshLease.acquire("successor.myshopify.com")

    from(lease in "shopifex_token_refresh_leases",
      where: lease.shop_url == "successor.myshopify.com"
    )
    |> Repo.update_all(set: [lease_expires_at: DateTime.add(DateTime.utc_now(), -1, :second)])

    assert {:ok, successor_owner} = TokenRefreshLease.acquire("successor.myshopify.com")
    assert :ok = TokenRefreshLease.release("successor.myshopify.com", stale_owner)

    assert %{owner: ^successor_owner} =
             Repo.one(
               from(lease in "shopifex_token_refresh_leases",
                 where: lease.shop_url == "successor.myshopify.com",
                 select: %{owner: lease.owner}
               )
             )
  end
end
