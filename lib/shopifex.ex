defmodule Shopifex do
  @moduledoc """
  Boilerplate for building Shopify **embedded** apps with Phoenix.

  Shopifex handles the modern Shopify app lifecycle: managed installation via
  token exchange, expiring offline access tokens (with background refresh),
  App Bridge session-token auth, GraphQL webhook subscriptions, and the
  Billing API.

  ## Installation

      def deps do
        [
          {:shopifex, "~> 3.0"}
        ]
      end

  ## Quickstart

  Run the install generator, then follow the printed `config.exs` and
  `router.ex` instructions:

      mix shopifex.install
      mix ecto.migrate

  Set your API credentials and Admin API version:

      config :shopifex,
        api_key: System.get_env("SHOPIFY_API_KEY"),
        secret: System.get_env("SHOPIFY_API_SECRET"),
        api_version: "2026-07"

  In your Shopify app config (`shopify.app.toml`), point the app URL at
  `https://your-app/auth`. New apps use **managed installation** — Shopify
  sends an `id_token` on every embedded load, which
  `Shopifex.Plug.ManagedInstall` verifies (`Shopifex.SessionToken`) and
  exchanges for an offline access token — no OAuth-redirect dance. (App Bridge
  still appends its short-lived `id_token` to each embedded load, and the
  library forwards it on the initial `/auth` hop; you just don't mint or thread
  an app token yourself the way 2.x did.)

  ## Authentication model

  Embedded auth is carried by Shopify's per-request `id_token` (App Bridge),
  not an app-issued cookie or JWT:

  - `Shopifex.Plug.ManagedInstall` — verifies the `id_token`, exchanges it for
    an **expiring** offline access token, persists the full token lifecycle,
    and re-exchanges on a staleness window. New shops are persisted through the
    configurable `Shopifex.ManagedInstall.Callbacks` hooks.
  - `Shopifex.Plug.ShopifySession` — verifies the session token on each
    embedded request and loads the shop.
  - `Shopifex.Plug.ShopifyApiAuth` — backs the `:shopify_api` pipeline for
    SPA → backend requests (`Authorization: Bearer <id_token>`).

  ## Expiring offline access tokens

  Required for public apps' GraphQL Admin API requests as of 2027-01-01 (custom
  and merchant-created apps are exempt). Tokens have a ~1h TTL and a
  90-day, one-time-use refresh token. Shopifex keeps them fresh on every path:

  - **Embedded** — `ManagedInstall` re-exchanges the `id_token` before expiry.
  - **Background** (schedulers, webhooks) — `Shopifex.Auth` refreshes via the
    stored refresh token, serialized per-shop with a dedicated database lease
    (one-time-use tokens can't be refreshed concurrently). The Shopify request
    does not hold a transaction or lock on the app's shop row.
  - **Every API call** — `Shopifex.API.graphql/3` refreshes proactively before
    a call and reactively on a `401`.

  Legacy / non-expiring installs (nil expiry columns) round-trip unchanged.

  ## Public API

  - `Shopifex.API` — GraphQL Admin API transport (the single chokepoint).
  - `Shopifex.Auth` — offline-token refresh for background paths.
  - `Shopifex.SessionToken` — strict HS256 verification of App Bridge tokens.
  - `Shopifex.Shops` — shop/plan/grant context + GraphQL webhook management.
  - `ShopifexWeb.Routes` — router pipelines and route macros.
  - `ShopifexWeb.AuthController`, `ShopifexWeb.PaymentController`,
    `ShopifexWeb.WebhookController` — overridable controller behaviours.
  """
end
