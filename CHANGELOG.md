# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.5.0] - 2026-09-14

### Added

- Support for Shopify's expiring offline access tokens (`config :shopifex, expiring_offline_access_tokens: true`). Install and update flows request an expiring token and persist the refresh token and expiries on the shop schema (`refresh_token`, `access_token_expires_at`, `refresh_token_expires_at`; configurable via `use Shopifex.Shop`).
- `Shopifex.OAuth` with the authorization code, refresh token and token exchange grants.
- `Shopifex.Shops.get_access_token/1`, `get_access_token!/1`, `ensure_fresh_access_token/1` and `refresh_access_token/1`. Refreshes are serialized per shop through the overridable `with_access_token_refresh_lock/2` and the token pair is persisted atomically. A rejected refresh token is cleared so the shop is sent back through OAuth.
- `Shopifex.Plug.EnsureAccessToken` (added to the `:shopify_session` and `:shopify_admin_link` pipelines) which upgrades shops without a refresh token via token exchange, falling back to the OAuth update flow.
- `Shopifex.AccessTokenError`.
- `config :shopifex, oauth_http_client:` to swap the OAuth HTTP client in tests.

### Changed

- Webhook management and payment charges obtain the access token through `Shopifex.Shops.get_access_token/1` instead of reading `shop.access_token` directly.
- `mix shopifex.gen.schemas` / `gen.migration` include the new token fields.

## [2.0.1] - 2021-08-25

### Added

- Ensure that the current shop scopes in the session are up-to-date based on config :shopifex, :scopes when the request is passed through :shopify_session or :shopify_admin_link pipelines.
- Add Shopifex.Plug.EnsureScopes plug which redirects to Shopify OAuth update if current shop scopes are not up-to-date

### Changed

## [2.0.0] - 2021-08-17

### Added

### Changed

- Move `show_plans` optional callback from `Shopifex.PaymentGuard` behaviour to `render_plans` in `ShopifexWeb.PaymentController` behavour

[unreleased]: https://github.com/ericdude4/shopifex/compare/v2.0.1...HEAD
[2.0.1]: https://github.com/ericdude4/shopifex/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/ericdude4/shopifex/compare/v1.1.1...v2.0.0
