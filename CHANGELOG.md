# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.0] - Unreleased

Modernization release: Shopify 2026 compliance, a Guardian-free embedded auth
model, and a Phoenix 1.8 / function-component baseline. Nothing from this
branch has been published to Hex yet (the latest published release is 2.4.0).

### Breaking changes

- **Minimum Elixir 1.15 and Phoenix 1.8.** Dropped `phoenix_view`,
  `phoenix_html_helpers`, and `plug_cowboy` — the library no longer pins a web
  server (Bandit is the Phoenix 1.8 default) or the legacy view stack.
  `phoenix_live_view ~> 1.0` is now a hard dependency (2.x pulled in none), so
  add it to your app's deps if it isn't already there. CI verifies Elixir
  1.15.8/OTP 26.2 (minimum) and Elixir 1.18.2/OTP 27.3 (current) against Phoenix
  1.8.8 / Phoenix LiveView 1.2.1 — see `.github/workflows/ci.yml`.
- **View layer is function components.** `Phoenix.View` modules + `.eex`
  templates were replaced by `*HTML` modules with co-located `.heex`
  templates. If you rendered Shopifex views directly, update to
  `put_view(ShopifexWeb.PaymentHTML)` / `render("show_plans.html", ...)`.
  `use ShopifexWeb, :view` is gone (it existed in 2.x; a 3.0 app that still
  calls it hits `UndefinedFunctionError`), and `controller/0` no longer
  injects `alias _.Router.Helpers, as: Routes` (which also shadowed
  `ShopifexWeb.Routes`).
- **Guardian removed.** Embedded auth no longer mints an app JWT. Session
  tokens (`id_token`) are verified directly by `Shopifex.SessionToken`.
  `Shopifex.Plug.build_session/4` no longer sets a Guardian token; the
  `:shopify_api` / `:shopifex_api` pipelines now use
  `Shopifex.Plug.ShopifyApiAuth`. `AuthController.auth/2` and
  `PaymentController` redirect to the app root instead of appending `?token=`.
  LiveView session keys are renamed `"shop_url"` / `"session_token"` (2.x used
  `"current_shop"`).
- **Webhooks and billing are GraphQL.** REST webhook (`webhooks.json`) and
  charge (`recurring_application_charges` / `application_charges`) endpoints
  were removed, along with the `neuron` dependency. `get_current_webhooks/1`
  returns `%{id, topic}` maps with GraphQL enum topics (e.g. `"ORDERS_CREATE"`,
  not `"orders/create"`). `Shopifex.Shops.delete_webhook/2` now takes a
  GraphQL `id` (a GID string, not a REST webhook id) and returns
  `{:ok, id} | {:error, errors}`.
- **Embedded payment routes are the default.** `payment_routes/2` defaults to
  the CSP-protected embedded pipeline; pass `shopify_embedded: false` to opt
  out.
- **Billing charges are cryptographically bound and verified with Shopify.**
  `complete_payment/2` requires a signed charge binding created by
  `ShopifexWeb.PaymentController.bind_charge/4` and verifies the charge's
  status with Shopify via the (new, overridable) `verify_charge/3` callback
  before creating a `Grant`. Any custom `select_plan`-style action **must**
  call `bind_charge/4` before redirecting to Shopify's confirmation URL, or
  `complete_payment/2` rejects the return with `403`. `create_charge/2` is
  also an overridable callback. `complete_payment/2` coerces the charge id (the
  trailing numeric segment of a GraphQL GID) to an integer with `Integer.parse/1`;
  the `:redirect_after_agent` store, `create_grant/3` (spec `charge_id ::
  pos_integer()`), and the `Grant.charge_id` `:bigint` column all key on that
  integer — only `verify_charge/3` receives the string form (to rebuild the GID).
  `Shopifex.RedirectAfterAgent` (and `Shopifex.RedirectAfter.Ecto`) now store
  opaque signed charge-binding strings, not raw redirect URLs — a custom
  `:redirect_after_agent` implementation must round-trip whatever
  `bind_charge/4` hands it, not assume a plain string.
- **`use_grant/2` (`Shopifex.PaymentGuard`) may return `nil`.** The default
  implementation now decrements `remaining_usages` atomically and returns
  `nil` when 0 rows were updated (the grant was already exhausted, e.g. a
  race between two requests); `Shopifex.Plug.PaymentGuard` treats that the
  same as no grant and redirects to the plan picker. Custom `use_grant/2`
  overrides must handle a `nil` return. `grant_for_guard/2` now prefers an
  unlimited grant (`remaining_usages == nil`) over a metered one when both
  unlock the same guard.
- **`Shopifex.Plug.EnsureScopes` defaults to `:raise`, not a redirect.** On a
  scope mismatch it now raises an actionable error pointing at managed-install
  app config instead of bouncing the merchant through legacy OAuth. Opt back
  into the 2.x redirect with
  `plug Shopifex.Plug.EnsureScopes, on_missing_scopes: :redirect` (or
  `config :shopifex, :ensure_scopes_on_missing, :redirect`).
- **Generated Grant/Plan schemas changed nullability.** `mix shopifex.install`
  now generates `Grant.charge_id`, `Grant.remaining_usages`, and `Plan.usages`
  as nullable (unlimited plans have no usage cap; `create_shop_grant/2` never
  supplies a `charge_id`), and `Grant.charge_id` is `:bigint` (Shopify charge
  ids exceed Postgres `int4`). Apps that regenerate schemas with
  `mix shopifex.install` should review their existing migrations.

### Security

- **`complete_payment/2` validates its params before consuming the charge
  binding, and restores the binding on any exception.** The signed binding was
  popped from the store before `plan_id` was compared with `to_string/1`, so an
  unauthenticated `?plan_id[x]=y` (a map) with a pending charge id and the
  public shop domain raised after the pop, skipped the restore-on-error
  branch, and left the merchant's own confirmation with no binding and no
  grant. `charge_id`, `plan_id` and `shop` must now be strings before the
  store is touched (Shopify's return URL always sends strings), and an
  exception raised after the pop (for example a plan deleted while the charge
  was pending) puts the binding back before re-raising.
- **Non-string query params are rejected before HMAC and timestamp checks.**
  A bracket-syntax param (`?timestamp[x]=y`, `?foo[x]=y`) parses to a map.
  `Shopifex.Plug.validate_timestamp/2` called `to_string/1` on it and the
  query-HMAC computation interpolated every value before any signature check,
  so unauthenticated input answered `500` instead of `401` on the
  `:shopify_proxy`, `:validate_install_hmac`, `:shopify_admin_link` and
  `:shopify_session` pipelines. `validate_timestamp/2` now returns
  `{:error, "malformed timestamp"}` for a non-string, non-integer value, and
  `Shopifex.Plug.hmac_matches?/2` returns `false` without computing anything
  unless every query value is a string (`ids`: a list of strings).
  `Shopifex.Plug.ManagedInstall` ignores non-string `id_token` / `shop`
  params, and `initialize_installation/2` forwards only a string `state`.
- **`Shopifex.SessionToken` validates the `dest` host with the anchored
  `Shopifex.ShopDomain.valid?/1` pattern** that `initialize_installation`
  already applies to the unsigned `shop` param, instead of a `.myshopify.com`
  suffix check. `dest` is inside the signed token, so this is defence in depth
  for the host that is interpolated into the token-exchange URL and stored as
  the shop's `url`.
- HMAC comparisons use constant-time `Plug.Crypto.secure_compare/2` everywhere
  (`ValidateHmac`, `ShopifyWebhook`, `ShopifySession`), and computed HMAC values
  are no longer logged on failure.
- Webhook Base64 HMACs are compared case-sensitively (no longer lowercased),
  matching Shopify JS/Ruby.
- Query / app-proxy HMAC parameters are signed in explicit alphabetical order.
- Query / app-proxy requests with a `timestamp` are rejected outside a
  90-second tolerance (`config :shopifex, :hmac_timestamp_tolerance_seconds`),
  via the shared `Shopifex.Plug.validate_timestamp/2` helper. The initial
  `/auth` session request (`Shopifex.Plug.ShopifySession`) now runs this same
  check, so a stale `timestamp` on an admin-load request is rejected too when
  one is present (still not required there, unlike `:shopify_proxy`). An
  iframe reload of a signed admin URL after the tolerance therefore renders the
  store-selection page unless the app re-authenticates through App Bridge; see
  `docs/upgrading.md` §5.
- **`Shopifex.Plug.ShopifySession` reads `shop` from the HMAC-signed query
  params, not the request params.** A POST body `shop` can no longer override
  the signed value used to look up and build the session.
- **`Shopifex.Plug.ShopifyWebhook` verifies the webhook body HMAC and resolves
  the shop from trusted sources only.** It gained a `:mode` option. In the
  default `:webhook` mode it checks the `x-shopify-hmac-sha256` header against
  the HMAC of the raw request body (new helper
  `Shopifex.Plug.valid_webhook_hmac?/1`) — a query-string `hmac` is ignored —
  and resolves the shop from the `x-shopify-shop-domain` header or the
  HMAC-verified body, never the merged `conn.params` (which a request body could
  shadow). Admin/bulk-action links use `mode: :admin_link` (set by the
  `:shopify_admin_link` pipeline), which verifies the query HMAC and a fresh
  timestamp and resolves the shop from the signed query.
- **`Shopifex.Plug.LoadProxyShop` reads the shop from the signed
  `conn.query_params`, not `conn.params`.** Shopify signs only the app-proxy
  query, so a `POST` body can no longer shadow the `shop` used to resolve the
  proxy request's shop.
- **`initialize_installation` validates the shop domain with an anchored
  pattern** (`Shopifex.ShopDomain.valid?/1`) instead of an unanchored regex,
  closing an open-redirect vector (a crafted `shop` value could previously
  pass a loose `.myshopify.com` substring check and redirect off-domain).
- **App-proxy requests now require a `timestamp`.** The `:shopify_proxy`
  pipeline passes `ValidateHmac, require_timestamp: true`, closing a replay
  window where a signed proxy URL without a timestamp was valid forever.
  Admin-load / bulk-action links (which may legitimately omit it) are
  unaffected.
- **CSP `frame-ancestors` no longer interpolates an unvalidated shop host.**
  `Shopifex.Plug.SetCSPHeader` now only adds the shop origin when the stored
  URL is a bare hostname, and adds its header alongside any existing CSP
  instead of replacing it, so a malformed/tampered URL can't inject extra
  directives.
- **Webhook dispatch fails closed on a missing/duplicate `x-shopify-topic`
  header** (`400`) instead of raising a `MatchError` (`500`).
- **Fixed a cross-tenant grant bypass in `PaymentGuard`.** The default
  `grant_for_guard/2` and `grants_for_shop/1` queries combined their filters
  with `where` + `or_where`, which Ecto OR-ed against the *whole* clause — the
  `remaining_usages > 0` branch dropped the `shop_id`/`guard` filters, so any
  shop's metered grant could satisfy another shop's payment check (and the OR
  branch could not use an index). The predicates are now AND-ed, with the `or`
  confined to the two `remaining_usages` alternatives.
- **Secret rotation.** Set `config :shopifex, :old_secret` to have webhook /
  app-proxy / session HMAC verification, session-token (`id_token`)
  verification, and the billing charge-binding signature accept the previous
  secret as well, so rotating the app secret doesn't drop in-flight webhooks,
  sessions, or an in-progress billing round-trip.
- **LiveView session no longer carries the shop's tokens.**
  `ShopifexWeb.LiveSession.put_shop_in_session/1` now serializes only the shop
  **URL** (not the `current_shop` struct), and `on_mount` reloads the shop
  server-side. The LV session is signed but not encrypted (readable
  client-side), so the old behavior exposed `access_token` / `refresh_token`.

### Added

- `Shopifex.Scopes` — `split/1` (comma-separated string, list, or `nil` → a
  trimmed list with empty segments dropped) and `missing/2` (required scopes
  the grant lacks, in required order), the shared scope-list parser behind
  `Shopifex.Plug.EnsureScopes` and `Shopifex.Plug.ManagedInstall`.
- `Shopifex.Auth` — background offline-token refresh: proactive refresh
  within a 5-minute safety window (`fresh_token/1`), reactive refresh on a
  401, and cross-node concurrency safety via a dedicated
  `shopifex_token_refresh_leases` table (one-time-use refresh tokens can't be
  refreshed concurrently without it). The outbound Shopify request holds
  neither a database connection nor a lock on the consumer's shop row; only a
  short final transaction (`SELECT ... FOR UPDATE`) re-checks token fields
  before persisting, so a concurrent managed-install exchange is never
  overwritten. Fresh installer migrations include the leases table; existing
  consumers of this branch must add the documented migration.
- **`Shopifex.Auth.fresh_token/1`** — public, returns `{:ok, shop} | {:error, reason}`
  (distinct from `ensure_fresh_token/1`, which always returns a shop and
  swallows the error). `Shopifex.Auth.terminal_refresh_error?/1` classifies a
  refresh failure as terminal (`:refresh_token_expired`, `:no_refresh_token`,
  `:shop_not_found`, `{:refresh_failed, 400 | 401}`) or transient (worth
  retrying with the shop's current token).
- **`{:error, :refresh_token_expired}`** — `Shopifex.Auth.refresh/1` now checks
  the stored `refresh_token_expires_at` (with a 60s skew) before contacting
  Shopify, turning a doomed round-trip into an immediate, specific failure. A
  `nil` expiry is never treated as expired, so legacy installs are unaffected.
  Token-expiry predicates throughout `Shopifex.Auth` and
  `Shopifex.Plug.ManagedInstall` accept both `DateTime` and `NaiveDateTime`
  columns.
- **Refresh retries on transient failures.** The refresh-token grant retries
  a request that times out or returns 408/429/500/502/503/504 up to 2 times
  with the *same* refresh token — the behaviour Shopify documents as
  returning the same rotated credentials rather than issuing another pair.
  Req's built-in `retry: :transient` can't be used here (it mishandles a
  float `Retry-After` value, which Shopify sends); a dedicated retry function
  honours `Retry-After` in integer or float seconds, capped at 5s per delay.
  A terminal 400/401 is not retried, so a genuinely spent refresh token still
  fails immediately. Each attempt uses a 5s connect / 10s receive timeout.
  Override via `config :shopifex, :req_options`.
- `Shopifex.API` — single GraphQL Admin API transport with a configurable
  `api_version` (default `2026-07`) and errors-take-precedence handling. A
  *terminal* token-refresh failure (expired/missing refresh token, a 400/401
  from Shopify's token endpoint, or shop not found) surfaces as
  `{:error, {:token_refresh_failed, reason}}` rather than a generic
  `{:error, {401, body}}` or a crashed request.
- `Shopifex.SessionToken` — strict HS256 verification of App Bridge session
  tokens, with `:expired` distinct from other errors.
- `Shopifex.Plug.ShopifyApiAuth` — session-token auth for the API pipelines.
- Token-lifecycle columns on the shop schema (`token_expires_at`,
  `refresh_token`, `refresh_token_expires_at`; `scope` now nullable), all
  additive and nullable so legacy / non-expiring installs round-trip.
- **Managed installation is the default embedded auth flow.** `auth_routes/1`
  now pipes `/auth` through `[:shopifex_browser, :managed_install,
  :shopify_session]`, so generated apps run token exchange out of the box.
  `Shopifex.Plug.ManagedInstall` verifies `id_token`, requests **expiring**
  tokens (`expiring=1`), persists the full token lifecycle, and re-exchanges
  when the stored `token_expires_at` is within ~10 minutes of expiry.
- `Shopifex.ManagedInstall.Callbacks` — configurable `insert_shop/1`,
  `after_install/1` (first install only), and `after_exchange/2` (every
  exchange — install **and** refresh, with a `new?` flag) hooks for the
  managed-install path (`config :shopifex, managed_install_callbacks:
  MyApp.Callbacks`). Callbacks run synchronously in the request — spawn a
  `Task` for slow work. The legacy `AuthController.after_install/3` /
  `insert_shop/1` callbacks apply only to the OAuth controller flow.
- `Shopifex.Plug.session_token/1` now also reads the `id_token` query parameter
  (in addition to `token` and `Authorization: Bearer`), and
  `Shopifex.Plug.ShopifySession` yields to a shop already loaded by
  `ManagedInstall` instead of re-authenticating.
- Default GDPR webhook handlers in `ShopifexWeb.WebhookController`
  (`customers/data_request`, `customers/redact`, `shop/redact`), overridable.
- `appPurchaseOneTimeCreate` support for one-time charges. `create_charge/2` is
  public and overridable, and the recurring mutation accepts optional
  `replacement_behavior`, `discount`, `currency_code`, and `line_items`
  (multiple items / usage pricing) from plan data. The new `verify_charge/3`
  callback checks the charge's status with Shopify before `complete_payment/2`
  creates a `Grant` (`AppSubscription` ACTIVE/ACCEPTED, `AppPurchaseOneTime`
  ACTIVE).
- `docs/parity-matrix.md` — behavior parity matrix vs Shopify JS and Ruby.
  `docs/upgrading.md` — step-by-step 2.x → 3.0 upgrade guide.
- `Shopifex.Test` — public test helpers (ships in the package) for forging the
  tokens/HMACs Shopifex verifies: `sign_session_token/2`, `put_shopify_session/3`,
  `sign_webhook/2`, `put_webhook_hmac/3`, `sign_query_hmac/2`. Lets consuming apps
  test controllers/LiveViews behind the `:shopify_*` pipelines without Shopify.
- `Shopifex.Plug.ShopifyApiAuth` now sets `x-shopify-retry-invalid-session-request: 1`
  on its `401`, so App Bridge's `authenticatedFetch` transparently retries with a
  fresh `id_token` (embedded tokens live ~60s) instead of surfacing the error.
- `jose` is now an explicit dependency.
- `Shopifex.RedirectAfter.Ecto` — a persistent, multi-node-safe implementation of
  the `Shopifex.RedirectAfterAgent` behaviour, backed by a `shopifex_charge_redirects`
  table (no supervised process to add). Configure with
  `config :shopifex, :redirect_after_agent, Shopifex.RedirectAfter.Ecto`;
  `mix shopifex.install` generates the config + migration for new apps. Use it
  instead of the in-memory default whenever the app runs on more than one node.
- **`config :shopifex, :configure_webhooks_on_exchange?`** (default `true`) —
  set `false` to skip the idempotent webhook reconcile on every token
  re-exchange (first install still registers). Set `:webhook_topics` to `[]`
  to disable Shopifex webhook registration entirely (e.g. TOML-managed
  webhooks) — `configure_webhooks/1` then makes no GraphQL call at all,
  rather than fetching current subscriptions to reconcile against nothing.
- **`Shopifex.Plug.ValidateHmac, require_timestamp: true`** — a per-plug option
  that rejects any signed request lacking a `timestamp` (default `false` keeps
  the existing "missing timestamp is allowed" behavior for non-proxy flows).
- **`Shopifex.Plug.LoadProxyShop`** — resolves the shop from a verified app-proxy
  request's signed `shop` param and exposes it via `Shopifex.Plug.current_shop/1`.
  Included by default in the `:shopify_proxy` pipeline (after `ValidateHmac`),
  so proxy controllers get `current_shop` without a bespoke plug. Pass
  `on_missing: :halt` to reject unknown shops with `401` (default `:pass` is
  non-breaking — `current_shop` is simply `nil`).
- **Per-pipeline HMAC timestamp tolerance.** `Shopifex.Plug.ValidateHmac` accepts
  a `timestamp_tolerance_seconds` plug option that overrides the global
  `config :shopifex, :hmac_timestamp_tolerance_seconds`, so an app-proxy pipeline
  can allow more clock/lag drift without widening the admin-load replay window.
- Legacy OAuth `install/2` and `update/2` send the authorization-code grant
  form-encoded with `expiring=1` and persist `token_expires_at` /
  `refresh_token_expires_at` via the same `Shopifex.TokenResponse.shop_attrs/2`
  helper the managed-install exchange uses, so legacy-flow shops also get the
  full token lifecycle. The default `AuthController.auth/2` forwards the
  complete signed query (not just embedded-context params) when no `id_token`
  is present, so a legacy non-embedded landing route still has an HMAC to
  re-verify.

### Fixed

- **Embedded pages render inside the Shopify admin again on Phoenix 1.8.**
  Phoenix 1.8's `put_secure_browser_headers/2` adds
  `content-security-policy: base-uri 'self'; frame-ancestors 'self';`, and
  `Shopifex.Plug.LoadInIframe` only deleted `x-frame-options`. Browsers enforce
  every CSP header, so that header blocked the admin iframe ("refused to
  connect") alongside the `frame-ancestors` policy `Shopifex.Plug.SetCSPHeader`
  adds. `LoadInIframe` now also drops the `frame-ancestors` directive from each
  `content-security-policy` header, keeping its other directives.

- **`Shopifex.Plug.EnsureScopes` normalises scope lists before comparing
  them.** `config :shopifex, :scopes` and the shop's stored `scope` were split
  with a bare `String.split/2`, so an empty `:scopes` config raised on every
  request under the new `:raise` default (the "missing" scope was `""`), a
  `nil` config crashed with a `FunctionClauseError`, and
  `"read_products, write_products"` (space after the comma) never matched
  Shopify's `"read_products,write_products"`; the legacy `:redirect` also sent
  `scope=,` for an empty config. `EnsureScopes` and
  `Shopifex.Plug.ManagedInstall` (which already trimmed) now both parse
  through `Shopifex.Scopes.split/1`: whitespace around scope names is ignored,
  empty segments are dropped, and an empty or `nil` `:scopes` config requires
  nothing. Missing scopes are reported trimmed, and the `:required_scopes`
  plug option also accepts a list of scope names.
- **Managed install: concurrent embedded loads no longer race the token
  exchange.** `Shopifex.Plug.ManagedInstall` now takes the per-shop
  `Shopifex.TokenRefreshLease` (the lease `Shopifex.Auth.refresh/1` already
  uses) around every `id_token` exchange. Two concurrent loads of a shop with
  a stale token previously both exchanged and the last response to arrive was
  persisted unconditionally, even when it had been issued first, leaving a
  refresh token Shopify had already retired (background refresh then failed
  until the next embedded load); two concurrent first loads both inserted the
  shop (raising on the unique `url` index, or leaving duplicate rows that made
  `get_shop_by_url/1` raise `Ecto.MultipleResultsError`). Now exactly one load
  exchanges; the others poll the shop row and build their session from the
  persisted pair without contacting Shopify, and a first install inserts the
  row once. A re-exchange of an existing shop is persisted with the same
  `FOR UPDATE` compare `Shopifex.Auth.refresh/1` uses
  (a `@doc false` `persist_token_pair/2` helper in `Shopifex.Auth`; the write no longer
  goes through `Shopifex.Shops.update_shop/2`), so a pair written concurrently
  is kept and `configure_webhooks` / `after_exchange` are skipped for the
  superseded exchange. A load that cannot obtain or observe the lease within
  `:token_refresh_wait_timeout_ms` (15 s default) logs a warning and exchanges
  without coordination, as before. **The `shopifex_token_refresh_leases` table
  is therefore required by the plug, not only by background refresh** (see
  `docs/upgrading.md` §2).
- **The plans page's Select request is authenticated outside the Shopify
  admin.** With `payment_routes(shopify_embedded: false)` the plans page is
  reached through the payment guard's path-bound `redirect_token`, but its
  Select button POSTed only `plan_id` / `redirect_after`, relying on App
  Bridge to attach the Bearer `id_token` — which it does only inside the admin
  iframe. Every non-embedded plan selection therefore fell to the store
  selector and the merchant could not pay (2.x posted a Guardian token in the
  same request). `ShopifexWeb.PaymentHTML.select_plan_path/1` now appends a
  `redirect_token` bound to the shop and to `/payment/select-plan` (valid for
  one hour) to the fetch URL when the page was authenticated without an
  `id_token`; `Shopifex.Plug.ShopifySession` accepts it there and nowhere
  else, so a captured page can at most start a pending charge the merchant
  must still approve. `Shopifex.Plug.sign_redirect/3` gains a `:max_age`
  option (default still 90 s) and embeds an explicit `exp` claim that
  `verify_redirect/2` enforces; tokens signed before this change (no `exp`)
  are rejected. Embedded pages render byte-identical output. If you override
  `render_plans/3` with your own template, POST to `select_plan_path(conn)`.
- **`Shopifex.Plug.FetchFlash` works on Phoenix 1.8.** It now delegates to
  `Phoenix.Controller.fetch_flash/2` — on Phoenix 1.7+ the plug it wrapped was
  a no-op and a subsequent `put_flash` raised.
- **`Shopifex.Plug.PaymentGuard` no longer needs `Router.Helpers`**, so it
  works with `helpers: false` routers. It builds the plan-picker redirect from
  `path_prefix` and `URI.encode_query/1` instead of a generated route helper.
- **Non-integer `charge_id` values respond `403` instead of crashing.**
  `complete_payment/2` parses `charge_id` with `Integer.parse/1` and rejects a
  non-integer value the same way as any other unverifiable confirmation,
  rather than raising.
- **Token refresh no longer performs Shopify HTTP inside a `SELECT … FOR UPDATE`
  transaction.** The outbound request now holds neither the consumer's shop row
  lock nor a database connection. A short final transaction re-checks token
  fields before persisting, preventing a concurrent managed-install exchange
  from being overwritten.
- **Legacy OAuth `install/2` and `update/2` are testable again.** Both were the
  only `Req.post` call sites that did not append
  `Application.get_env(:shopifex, :req_options, [])`, so the authorization-code
  grant could not be stubbed and had no test coverage at all — including the
  `String.to_atom/1` whitelist fix below. They now follow the same pattern as
  `Shopifex.Auth`, `Shopifex.API`, and `Shopifex.Plug.ManagedInstall`, and are
  covered by tests for the success path, a rejected code, token rotation on
  update, and the response whitelist.
- **`complete_payment/2` no longer 500s on a redirect-cache miss.** It now
  responds `403` (a `Plug.Conn`) instead of returning a bare `{:error, :forbidden}`
  tuple, which raised unless the app had wired an `action_fallback`.
- **Managed-install `auth/2` redirect carries embedded-context params.** The
  redirect to the app root now forwards `shop`/`host`/`id_token` so App Bridge can
  re-initialize on the landing page (a server 302 doesn't inherit them and
  third-party cookies are blocked), and the landing route's `:shopify_session` can
  authenticate the hop.
- **Legacy OAuth `install`/`update` no longer call `String.to_atom/1`** on the
  token response (atom-exhaustion hardening) — known response keys are mapped via
  a fixed whitelist.
- **`mix shopifex.gen.migration` now indexes `grants.shop_id`.** The generated
  `grants` table only had a GIN index on `grants`; `grant_for_guard/2` filters by
  `shop_id` on every guarded request, so a plain btree index is now emitted (the
  migration generator gained an `:index` index type).
- **`mix shopifex.install`'s generated Grant schema compiles.** It previously
  emitted an invalid `field :shop_id, {:references, ...}`. The generated
  migration also creates `shopifex_charge_redirects`, and the grants→shops
  foreign key is `on_delete: :delete_all`.
- **Managed-install token refresh is driven by token expiry, not `updated_at`.**
  `Shopifex.Plug.ManagedInstall` now re-exchanges the offline access token when
  `token_expires_at` is within ~10 minutes of expiry (consistent with
  `Shopifex.Auth`), instead of when the shop row's `updated_at` aged past 50
  minutes — an unrelated update to the shop row no longer masks an expired token.
- **Macro billing flow now creates the grant.** `Shopifex.RedirectAfterAgent`
  `set/2` and `get/1` disagreed on key type (string vs integer), so the
  charge-id keyed lookup in `complete_payment/2` missed and the `Grant` was never
  created. Both now coerce the key consistently.
- **Multi-node billing no longer drops grants.** The billing redirect store is
  the in-memory, node-local `Shopifex.RedirectAfterAgent` by default, so on a
  multi-node deploy (Fly.io, multiple pods) Shopify's `/payment/complete`
  redirect could land on a node with no cache entry — the merchant was charged
  but no `Grant` was created, **silently**. Two changes fix this: (1)
  `Shopifex.RedirectAfter.Ecto` is a shipped, DB-backed implementation that is
  safe across nodes (see Added), and `mix shopifex.install` now generates it as
  the default for new apps; (2) when the lookup misses, `complete_payment/2`
  logs an actionable `Logger.error` instead of failing silently.
- **Legacy OAuth authorization URLs are properly encoded.**
  `Shopifex.Plug.ShopifySession`'s install redirect and
  `Shopifex.Plug.EnsureScopes`'s re-authorization redirect now build their query
  string with `URI.encode_query/1`, so `scope` and `redirect_uri` are
  percent-encoded rather than interpolated raw. Also removed an unused
  `require Logger` from `Shopifex.Plug.ShopifyApiAuth`.
- **Managed install picks up approved scope updates.** When a shop's stored
  `scope` lacks a scope listed in `config :shopifex, :scopes`,
  `Shopifex.Plug.ManagedInstall` re-exchanges the `id_token` even though the
  access token is still fresh, and persists Shopify's current grant. Previously
  a merchant who had approved new scopes hit `EnsureScopes`'s raise until the
  token aged into the refresh window — never, for a legacy nil-expiry shop.
- **`Shopifex.Plug.PaymentGuard`'s redirect stays authenticated without an
  App Bridge token.** The redirect to `/payment/show-plans` now carries a
  short-lived `redirect_token` (`Shopifex.Plug.sign_redirect/3`, 90 s) bound
  to the plans path, in addition to forwarding an `id_token` as `token` when
  one is present. `Shopifex.Plug.ShopifySession` accepts the token only at the
  path signed into it, so a captured link cannot authenticate any other route
  or be used to mint a fresh credential. A legacy HMAC-authenticated or
  non-embedded request therefore reaches the plans page instead of the store
  selector.

### Changed

- **Webhook reconciliation lists up to 250 subscriptions** (Shopify's maximum
  page size) instead of 100, so a topic past the first page is not re-created
  and delivered twice. The list is per app and per shop and Shopifex creates
  one subscription per configured topic, so the query is not paginated.
- The default Shopify Admin GraphQL API version is `2026-07`
  (`config :shopifex, :api_version`).
- **Billing mutations no longer send `@idempotent`.** Shopify does not document
  the directive for `appSubscriptionCreate` / `appPurchaseOneTimeCreate`, and the
  official JS/Ruby libraries omit it. Recurring line items are passed as a
  `$lineItems` GraphQL variable rather than interpolated into the query.
- **Webhook subscriptions self-heal.** `Shopifex.Plug.ManagedInstall` now
  reconciles webhooks (idempotent `configure_webhooks/1`) on existing-shop token
  re-exchanges, not just first install — recovering from a registration that
  failed at install or topics added to `:webhook_topics` later. It runs at the
  token-exchange cadence (at the same ~10-minute-before-expiry cadence as the
  token refresh itself), never on the hot per-load path.
- **Built-in pages use the Shopify-hosted App Bridge + Polaris web components.**
  The auth / payment / redirect pages now load App Bridge and Polaris from
  `cdn.shopify.com` with a `<meta name="shopify-api-key">` tag, and are rendered
  with Polaris web components (`s-page`, `s-section`, …) — no React. The vendored
  `@shopify/app-bridge@3` + Polaris 4/7 bundle (`assets/`, `priv/static/`) was
  removed, so apps **no longer need** the `Plug.Static at: "/shopifex-assets"`
  endpoint entry. The `mix shopifex.install` task no longer prints it.
- **`postgrex` is now a `:dev`/`:test`-only dependency.** The library never calls
  Postgrex directly (only the test dummy repo does); downstream apps already bring
  their own driver.
- **`cors_plug` constraint widened to `~> 2.0 or ~> 3.0`** so downstream apps
  aren't pinned to the 2.x line.
- Tests use `Req.Test` stubs; `exvcr` and its cassettes were removed, along
  with orphaned `mix.lock` entries (`jsx`, `exjsx`, `meck`) left over from it.

## [2.0.1] - 2021-08-25

### Added

- Ensure that the current shop scopes in the session are up-to-date based on config :shopifex, :scopes when the request is passed through :shopify_session or :shopify_admin_link pipelines.
- Add Shopifex.Plug.EnsureScopes plug which redirects to Shopify OAuth update if current shop scopes are not up-to-date

### Changed

## [2.0.0] - 2021-08-17

### Added

### Changed

- Move `show_plans` optional callback from `Shopifex.PaymentGuard` behaviour to `render_plans` in `ShopifexWeb.PaymentController` behavour

[3.0.0]: https://github.com/ericdude4/shopifex/compare/v2.0.1...master
[2.0.1]: https://github.com/ericdude4/shopifex/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/ericdude4/shopifex/compare/v1.1.1...v2.0.0
