# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
