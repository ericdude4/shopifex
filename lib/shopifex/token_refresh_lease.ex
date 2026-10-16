defmodule Shopifex.TokenRefreshLease do
  @moduledoc """
  Cross-node lease used to serialize refreshes of Shopify's one-time-use
  offline refresh tokens.

  The lease lives in its own `shopifex_token_refresh_leases` table so the
  Shopify HTTP request never holds a lock on the consumer's shop row or a
  checked-out database connection. A crashed owner is recoverable after the
  lease expires. As with any refresh-token rotation, a process crash after
  Shopify accepts the token but before the new pair is persisted still
  requires a fresh managed-install exchange.

  Existing consumers of this branch must create the table before using expiring
  offline-token refresh:

      create table(:shopifex_token_refresh_leases, primary_key: false) do
        add :shop_url, :string, primary_key: true
        add :owner, :string, null: false
        add :lease_expires_at, :utc_datetime_usec, null: false
      end

  The lease is keyed by Shopify domain rather than the consumer schema's
  primary key, so it works with integer IDs, binary IDs, and custom shop
  schemas.
  """

  import Ecto.Query

  @table "shopifex_token_refresh_leases"
  @default_lease_ttl_ms 120_000
  @default_wait_timeout_ms 15_000
  @default_poll_interval_ms 100

  @type owner :: String.t()

  @doc false
  @spec acquire(String.t()) :: {:ok, owner()} | :busy
  def acquire(shop_url) when is_binary(shop_url) do
    repo = Shopifex.Shops.repo()
    owner = Ecto.UUID.generate()
    now = DateTime.utc_now()
    lease_expires_at = DateTime.add(now, lease_ttl_ms(), :millisecond)

    replace_expired_lease =
      from(lease in @table,
        where: lease.lease_expires_at <= ^now,
        update: [set: [owner: ^owner, lease_expires_at: ^lease_expires_at]]
      )

    case repo.insert_all(
           @table,
           [
             %{
               shop_url: shop_url,
               owner: owner,
               lease_expires_at: lease_expires_at
             }
           ],
           on_conflict: replace_expired_lease,
           conflict_target: [:shop_url]
         ) do
      {1, _rows} -> {:ok, owner}
      {0, _rows} -> :busy
    end
  end

  @doc false
  @spec release(String.t(), owner()) :: :ok
  def release(shop_url, owner) when is_binary(shop_url) and is_binary(owner) do
    repo = Shopifex.Shops.repo()

    from(lease in @table,
      where: lease.shop_url == ^shop_url and lease.owner == ^owner
    )
    |> repo.delete_all()

    :ok
  end

  @doc false
  @spec wait_timeout_ms() :: non_neg_integer()
  def wait_timeout_ms,
    do: duration!(:token_refresh_wait_timeout_ms, @default_wait_timeout_ms, allow_zero?: true)

  @doc false
  @spec poll_interval_ms() :: pos_integer()
  def poll_interval_ms,
    do: duration!(:token_refresh_poll_interval_ms, @default_poll_interval_ms)

  defp lease_ttl_ms,
    do: duration!(:token_refresh_lease_ttl_ms, @default_lease_ttl_ms)

  defp duration!(key, default, opts \\ []) do
    value = Application.get_env(:shopifex, key, default)
    allow_zero? = Keyword.get(opts, :allow_zero?, false)

    if is_integer(value) and (value > 0 or (allow_zero? and value == 0)) do
      value
    else
      raise ArgumentError,
            "expected config :shopifex, #{inspect(key)} to be " <>
              if(allow_zero?, do: "a non-negative integer", else: "a positive integer")
    end
  end
end
