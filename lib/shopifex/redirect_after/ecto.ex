defmodule Shopifex.RedirectAfter.Ecto do
  @moduledoc """
  Persistent, multi-node-safe implementation of the
  `Shopifex.RedirectAfterAgent` behaviour, backed by a database table instead of
  an in-memory `Agent`.

  Use this (not the default in-memory `Shopifex.RedirectAfterAgent`) whenever the
  app runs on more than one node. Shopify's `/payment/complete` redirect is a
  fresh top-level navigation with no session affinity, so behind a load balancer
  (Fly.io, multiple k8s pods, …) it can land on a *different* node than the one
  that ran `select_plan`. A node-local cache misses there and the `Grant` is
  silently dropped; a shared table does not.

  ## Setup

  1. Configure it as the redirect-after store:

         config :shopifex, :redirect_after_agent, Shopifex.RedirectAfter.Ecto

     (`mix shopifex.install` generates this line and the migration below for new
     apps.) There is **no process to add to your supervision tree** — unlike the
     in-memory agent, this module is stateless and talks to `Shopifex.Shops.repo()`
     directly.

  2. Add a migration for the backing table:

         defmodule MyApp.Repo.Migrations.CreateShopifexChargeRedirects do
           use Ecto.Migration

           def change do
             create table(:shopifex_charge_redirects, primary_key: false) do
               add :charge_id, :bigint, primary_key: true
               add :redirect_after, :text, null: false
               add :inserted_at, :utc_datetime, null: false
             end
           end
         end

  ## Semantics

  Matches `Shopifex.RedirectAfterAgent` exactly:

    * `set/2` upserts `charge_id -> redirect_after`. A binary charge id is coerced
      to an integer with `Integer.parse/1` (treating non-integers as a no-op `:ok`).
    * `get/1` is **one-shot**: it deletes the row and returns its `redirect_after`,
      or `nil` if there is no entry (treating non-integer binary ids as `nil`).
  """
  @behaviour Shopifex.RedirectAfterAgent

  import Ecto.Query, only: [from: 2]

  @table "shopifex_charge_redirects"

  @impl Shopifex.RedirectAfterAgent
  def set(charge_id, redirect_uri) when is_binary(charge_id) do
    case Integer.parse(charge_id) do
      {int_id, ""} -> set(int_id, redirect_uri)
      _ -> :ok
    end
  end

  @impl Shopifex.RedirectAfterAgent
  def set(charge_id, redirect_uri) when is_integer(charge_id) do
    repo = Shopifex.Shops.repo()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    repo.insert_all(
      @table,
      [[charge_id: charge_id, redirect_after: redirect_uri, inserted_at: now]],
      on_conflict: {:replace, [:redirect_after, :inserted_at]},
      conflict_target: :charge_id
    )

    :ok
  end

  def set(_charge_id, _redirect_uri), do: :ok

  @impl Shopifex.RedirectAfterAgent
  def get(charge_id) when is_binary(charge_id) do
    case Integer.parse(charge_id) do
      {int_id, ""} -> get(int_id)
      _ -> nil
    end
  end

  @impl Shopifex.RedirectAfterAgent
  def get(charge_id) when is_integer(charge_id) do
    repo = Shopifex.Shops.repo()

    {_count, rows} =
      from(r in @table, where: r.charge_id == ^charge_id, select: r.redirect_after)
      |> repo.delete_all()

    case rows do
      [redirect_after | _] -> redirect_after
      _ -> nil
    end
  end

  def get(_), do: nil
end
