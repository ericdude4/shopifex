defmodule Shopifex.RedirectAfterAgent do
  @moduledoc """
  Caches the post-payment charge binding keyed by Shopify charge id, so
  `complete_payment/2` can recover and verify it when Shopify redirects the merchant back.

  Values stored here are opaque signed charge-binding strings produced by
  `ShopifexWeb.PaymentController.bind_charge/4`.

  ## Multi-node deploys: use `Shopifex.RedirectAfter.Ecto`

  This default implementation is an in-memory `Agent` local to **one node**. A
  charge confirmation can redirect to `/payment/complete` on a *different* node
  than the one that handled `select_plan` (e.g. behind a load balancer / on a
  multi-node deploy like Fly.io), in which case the lookup misses and the grant
  is not created. It is intermittent and won't show up in single-node dev.

  If you run more than one node, configure the shipped, multi-node-safe
  `Shopifex.RedirectAfter.Ecto` (a DB-backed table) instead:

      config :shopifex, :redirect_after_agent, Shopifex.RedirectAfter.Ecto

  `mix shopifex.install` generates that config and the backing migration for new
  apps. Any module implementing this behaviour works — the config seam is just
  `Application.get_env(:shopifex, :redirect_after_agent, __MODULE__)`.

  When a lookup misses, `complete_payment/2` logs an actionable `Logger.error`
  (the usual cause is this node-local cache on a multi-node deploy), so dropped
  grants are observable rather than invisible.

  `set/2` and `get/1` agree on key type: both coerce binary ids with `Integer.parse/1`
  and treat non-integers as a miss (`nil` / no-op `:ok`) without raising.
  """
  use Agent
  require Logger

  @doc """
  Retrieve the redirect url from cache with key charge_id and
  remove the key from cache.
  """
  @callback get(charge_id :: String.t() | pos_integer()) :: String.t() | nil

  @doc """
  Set a redirect url in cache with key charge_id.
  """
  @callback set(charge_id :: String.t() | pos_integer(), redirect_uri :: String.t()) :: :ok

  def start_link(_) do
    Logger.info("Starting redirect_uri agent")
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def get(charge_id) when is_binary(charge_id) do
    case Integer.parse(charge_id) do
      {int_id, ""} -> get(int_id)
      _ -> nil
    end
  end

  def get(charge_id) when is_integer(charge_id) do
    Logger.info("Getting redirect_uri for charge #{charge_id}")
    redirect_uri = Agent.get(__MODULE__, &Map.get(&1, charge_id))
    Logger.info("Clearing redirect_uri for charge #{charge_id}")
    Agent.update(__MODULE__, &Map.delete(&1, charge_id))
    redirect_uri
  end

  def get(_), do: nil

  def set(charge_id, redirect_uri) when is_binary(charge_id) do
    case Integer.parse(charge_id) do
      {int_id, ""} -> set(int_id, redirect_uri)
      _ -> :ok
    end
  end

  def set(charge_id, redirect_uri) when is_integer(charge_id) do
    Logger.info("Storing redirect_uri for charge #{charge_id}")
    Agent.update(__MODULE__, &Map.put(&1, charge_id, redirect_uri))
  end

  def set(_charge_id, _redirect_uri), do: :ok
end
