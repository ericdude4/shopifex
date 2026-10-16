<img width="350" src="https://github.com/ericdude4/shopifex/raw/master/guides/images/logo.png" alt="Shopifex">

---

[![Hex.pm](https://img.shields.io/hexpm/v/shopifex.svg)](https://hex.pm/packages/shopifex)

Shopifex is a Phoenix library for building Shopify **embedded apps**. Version
3.0 targets Shopify's current (2026) embedded-app model: managed installation
via token exchange, expiring offline access tokens with background refresh,
the GraphQL Admin API for webhooks and billing, App Bridge session-token
authentication, and a Phoenix 1.8 baseline.

## Installation

```elixir
def deps do
  [
    {:shopifex, "~> 3.0"}
  ]
end
```

## Learning resources

- **[Parity matrix](docs/parity-matrix.md)** — how Shopifex compares to Shopify's
  official JS and Ruby libraries.

## Upgrading from 2.x

See [`docs/upgrading.md`](docs/upgrading.md) for the migration steps
(dependency, database migrations, config keys, router, billing, LiveView) and
a post-upgrade smoke-test checklist.

## Quickstart
#### Run the install script
This will install all of the supported Shopifex features.
```
mix shopifex.install
```
Follow the output `config.ex` and `router.ex` instructions from the install script.
#### Run migrations
```
mix ecto.migrate
```
#### Update Shopify app details
With **managed installation** (the default for new embedded apps), Shopify loads
your app with a fresh `id_token` on every page load and the `:managed_install`
pipeline exchanges it for an offline access token — no OAuth redirect URLs are
required. Declare your access scopes in `shopify.app.toml` (`[access_scopes]`).

Replace the tunnel URL with your own where applicable.
- Set "App URL" to `https://my-app.ngrok.io/auth`
- Add your Shopify app's API key and API secret key to
  `config :shopifex, api_key: "your-api-key", secret: "your-api-secret"`

> **Legacy OAuth (compatibility only):** if you still rely on the authorization-code
> OAuth flow, also add `https://my-app.ngrok.io/auth/install` and
> `https://my-app.ngrok.io/auth/update` to your app's "Allowed redirection URL(s)"
> and set `redirect_uri` / `reinstall_uri` in config (see below). New apps should
> not need these.

## Manual Installation
Create the shop schema where the installation data will be stored. Include the
token-lifecycle columns so Shopify's **expiring** offline tokens (required for
public apps' GraphQL Admin API requests from January 1, 2027) can be refreshed
in the background:
```
mix phx.gen.schema Shop shops url:string access_token:string scope:string \
  token_expires_at:utc_datetime refresh_token:string refresh_token_expires_at:utc_datetime
mix ecto.migrate
```
The four token columns are nullable — legacy/non-expiring installs round-trip with
`nil` expiry values. (`mix shopifex.install` generates this schema for you.)

Managed install and background refresh also need a short-lived, cross-node
lease table: `Shopifex.Plug.ManagedInstall` takes a per-shop lease around
every `id_token` exchange, and `Shopifex.Auth` around every refresh-token
grant. New `mix shopifex.install` migrations include it. When upgrading an existing app,
run `mix ecto.gen.migration create_shopifex_token_refresh_leases`, then add:

```elixir
create table(:shopifex_token_refresh_leases, primary_key: false) do
  add :shop_url, :string, primary_key: true
  add :owner, :string, null: false
  add :lease_expires_at, :utc_datetime_usec, null: false
end
```

The Shopify token request runs outside a database transaction; only a short
compare-and-persist step locks the shop row after the response arrives.

Add the `:shopifex` config settings to your `config.ex`. The config keys that
3.0 adds or changes, with their defaults, are listed in
[`docs/upgrading.md`](docs/upgrading.md#5-config-keys).

```elixir
config :shopifex,
  app_name: "MyApp",
  shop_schema: MyApp.Shop,
  web_module: MyAppWeb, # emitted by mix shopifex.install; not read by the library itself
  repo: MyApp.Repo,
  webhook_uri: "https://myapp.ngrok.io/webhook",
  scopes: "read_inventory,write_inventory,read_products,write_products,read_orders",
  api_key: "shopifyapikey123",
  secret: "shopifyapisecret456",
  api_version: "2026-07", # Admin GraphQL API version used by Shopifex.API
  webhook_topics: ["app/uninstalled"], # These are automatically subscribed on a store upon install
  shops_context_client: Shopifex.ShopsContextClient # Optional. Overridable context module which Shopifex uses to fetch and manage common app state

# Optional managed-install hooks (customise shop creation / post-install side effects):
#   managed_install_callbacks: MyApp.ManagedInstallCallbacks

# Legacy OAuth fallback only — not needed for managed installation:
#   redirect_uri: "https://myapp.ngrok.io/auth/install",
#   reinstall_uri: "https://myapp.ngrok.io/auth/update",
```

> **Webhooks — choose one mechanism, not both.** `:webhook_topics` registers
> webhook subscriptions imperatively via the GraphQL Admin API, on install and
> on every token re-exchange. If you instead declare webhooks declaratively in
> `shopify.app.toml` (`[webhooks]`, Shopify's modern recommended path), **set
> `webhook_topics: []`**. Otherwise Shopifex reconciles against Shopify's
> `webhookSubscriptions` query — which returns only shop-scoped (API-created)
> subscriptions, *not* your TOML/app-config ones — so each TOML topic looks
> unregistered and gets a duplicate API subscription, and the store can receive
> every event twice.

Update your `endpoint.ex` to include the custom body parser. This is necessary for HMAC validation to work.

```elixir
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  body_reader: {ShopifexWeb.CacheBodyReader, :read_body, []},
  json_decoder: Phoenix.json_library()
```

Add this line near the top of `router.ex` to include the Shopifex pipelines

```elixir
require ShopifexWeb.Routes
ShopifexWeb.Routes.pipelines()
```
Now the following pipelines are accessible:

- `:managed_install` -> Runs `Shopifex.Plug.ManagedInstall`: verifies Shopify's `id_token`, exchanges it for an expiring offline access token, and builds the session. Already included in `auth_routes/1` before `:shopify_session`.
- `:shopify_session` -> Verifies the App Bridge `id_token` (or the legacy HMAC), and makes session information available via `Shopifex.Plug` API. No-ops when `:managed_install` already loaded the shop. Also removes iFrame blocking headers so app can render in Shopify admin.
- `:validate_install_hmac` -> Runs `Shopifex.Plug.ValidateHmac` only. Used by the legacy OAuth `/auth/install` and `/auth/update` routes, which verify the query HMAC without loading a shop into the session.
- `:shopify_webhook` -> Validates Shopify webhook request HMAC (Base64, constant-time) and makes session information available via `Shopifex.Plug` API.
- `:shopify_admin_link` -> Validates Shopify admin link & bulk action link requests and makes session information available via `Shopifex.Plug` API.
- `:shopify_api` -> Ensures that a valid Shopify session token is present in the `Authorization` header. Useful for async requests between your SPA front end and Shopifex backend.
- `:shopify_proxy` -> Validates [App proxy](https://shopify.dev/docs/apps/build/online-store/display-dynamic-data) requests (signed with `signature`, not `hmac`) via `Shopifex.Plug.ValidateHmac, require_timestamp: true`, then resolves the shop with `Shopifex.Plug.LoadProxyShop`.
- `:shopify_embedded` -> Runs `Shopifex.Plug.SetCSPHeader`, restricting app loading to within the Shopify admin. Included by default in `payment_routes/2`'s plan-selection pages (pass `shopify_embedded: false` to opt out). With `shopify_embedded: false` the plans page authenticates its Select POST with a `redirect_token` bound to `/payment/select-plan` (valid for one hour) instead of App Bridge's Bearer `id_token`; if you override `render_plans/3` with your own template, POST to `ShopifexWeb.PaymentHTML.select_plan_path(conn)` so the credential is carried.
- `:shopifex_browser` -> Same as your normal `:browser` pipeline, except it calls `Shopifex.Plug.LoadInIframe`.

Now add this basic example of these plugs in action in `router.ex`. These endpoints need to be added to your Shopify app whitelist

### Routing
```elixir
# Include all auth (managed installation, plus legacy OAuth install/update) routes.
# The generated `/auth` route runs the `:managed_install` pipeline before
# `:shopify_session`, so token exchange happens automatically on app load.
ShopifexWeb.Routes.auth_routes(MyAppWeb.AuthController)

# Endpoints accessible within the Shopify admin panel iFrame.
# Don't include this scope block if you are creating a SPA.
scope "/", MyAppWeb do
  pipe_through [:shopifex_browser, :shopify_session]

  get "/", PageController, :index
end

# Make your webhook endpoint look like this
scope "/webhook", MyAppWeb do
  pipe_through [:shopify_webhook]

  post "/", WebhookController, :action
end

# Place your admin link endpoints in here
scope "/admin-links", MyAppWeb do
  pipe_through [:shopify_admin_link]

  get "/do-a-thing", AdminLinkController, :do_a_thing
end
```

Create a new controller called `auth_controller.ex` to handle the initial iFrame load and installation

```elixir
defmodule MyAppWeb.AuthController do
  use MyAppWeb, :controller
  use ShopifexWeb.AuthController

  # Thats it! Validation, installation are now handled for you :)
  
  # Optionally, override the `after_install` callback
  def after_install(conn, shop, oauth_state) do
    # TODO: send yourself an e-mail
    # follow default behaviour.
    super(conn, shop, oauth_state)
  end
end
```

> **Which install callback fires?** The `after_install/3` and `insert_shop/1`
> callbacks shown here are the **legacy OAuth** `AuthController` callbacks — they
> run only in the authorization-code `install/2` flow. **Managed installation
> runs in a plug, before any controller**, so it does not call them. For
> managed-install side effects, configure `Shopifex.ManagedInstall.Callbacks` —
> `insert_shop/1`, `after_install/1` (first install only), and `after_exchange/2`
> (every token exchange, install and refresh) — via
> `config :shopifex, managed_install_callbacks: MyApp.ManagedInstallCallbacks`.

Setting up your application as a SPA? Read this before continuing [Single Page Applications](#single-page-applications)

create another controller called `webhook_controller.ex` to handle incoming Shopify webhooks (optional)

```elixir
defmodule MyAppWeb.WebhookController do
  use MyAppWeb, :controller
  use ShopifexWeb.WebhookController

  # add as many handle_topic/3 functions here as you like! This basic one handles app uninstallation
  def handle_topic(conn, shop, "app/uninstalled") do
    Shopifex.Shops.delete_shop(shop)

    conn
    |> send_resp(200, "success")
  end

  # Mandatory Shopify shop data erasure GDPR webhook. Simply delete the shop record
  def handle_topic(conn, shop, "shop/redact") do
    Shopifex.Shops.delete_shop(shop)

    conn
    |> send_resp(204, "")
  end

  # Mandatory Shopify customer data erasure GDPR webhook. Simply delete the shop (customer) record
  def handle_topic(conn, shop, "customers/redact") do
    # If you store customer data you can delete it here.

    conn
    |> send_resp(204, "")
  end

  # Mandatory Shopify customer data request GDPR webhook.
  def handle_topic(conn, _shop, "customers/data_request") do
    # Send an email of the shop data to the customer.
    conn
    |> send_resp(202, "Accepted")
  end
end
```
## Maintaining session between page loads for server-rendered applications
With managed installation you no longer pass tokens around yourself. Shopify's
App Bridge appends a fresh `id_token` to every embedded page load (and sends it as
an `Authorization: Bearer` token on authenticated fetches). The `:managed_install`
and `:shopify_session` pipelines verify that token and load the shop, so a plain
link to another `:shopify_session` route just works:

```heex
<.link navigate={~p"/"}>home</.link>
```

`Shopifex.Plug.current_shop(conn)` is available in any request that passes through
a `:shopify_session`, `:managed_install`, or `:shopify_proxy` pipeline. (For
`:shopify_proxy`, `Shopifex.Plug.LoadProxyShop` resolves the shop from the signed
`shop` param once the HMAC is verified; it is `nil` if that shop isn't in your
database — see [App proxy](#app-proxy).) For LiveView, use the
`shopifex_live_session` macro below.

> **Legacy (v2) token-in-URL pattern.** Older apps threaded
> `Shopifex.Plug.session_token(conn)` through a `token` query parameter on every
> link/form. `session_token/1` still reads `id_token`, `token`, and the `Bearer`
> header, but the value it reads is now Shopify's short-lived (~60s) `id_token`,
> not an app-issued token — carrying it in a link only survives the *immediate*
> hop, not a full session. For managed-install apps the supported path is App
> Bridge's full-page reload (a fresh `id_token` on every load) and
> `authenticatedFetch`/`fetch` for XHR, not hand-carried query params.

## App proxy

[App proxy](https://shopify.dev/docs/apps/build/online-store/display-dynamic-data)
requests are signed with a `signature` param (not the admin `hmac`). The
`:shopify_proxy` pipeline verifies that signature and loads the shop:

```elixir
scope "/proxy", MyAppWeb do
  pipe_through [:shopify_proxy]

  get "/", ProxyController, :show
end
```

In the controller the shop resolved from the signed `shop` param is available as
`Shopifex.Plug.current_shop(conn)` (`nil` if that shop isn't in your database).
`Shopifex.Plug.LoadProxyShop` does this right after `Shopifex.Plug.ValidateHmac`;
pass `on_missing: :halt` to reject unknown shops with a `401` instead of passing
through. The built-in `:shopify_proxy` pipeline passes
`ValidateHmac, require_timestamp: true`, so a signed proxy URL without a
`timestamp` is rejected rather than replayable forever.

Storefront / proxy requests can legitimately lag past the default 90s HMAC
`timestamp` tolerance. Relax it for the proxy pipeline **only** (without widening
the admin-load replay window) with a per-plug option — build your own pipeline.
Keep `require_timestamp: true` so you don't lose the replay protection:

```elixir
pipeline :shopify_proxy_relaxed do
  plug :fetch_session
  plug Shopifex.Plug.FetchFlash
  plug Shopifex.Plug.ValidateHmac, timestamp_tolerance_seconds: 600, require_timestamp: true
  plug Shopifex.Plug.LoadProxyShop
end
```

## Using LiveView in your embedded app
There are two special considerations to using LiveView in your embedded app.

First, you'll need to get the LiveView socket configured to work in the Shopify iframe. This [elixir](https://elixirforum.com/t/how-to-embed-a-liveview-via-iframe/65066) post gives some excellent tips.

Second, use the `:embedded` on_mount hook so LiveView reads the shop from the
Phoenix session set during the HTTP request, instead of requiring tokens in
URLs or LiveSocket connect params. `@current_shop` is your authenticated Shop
resource. **`@session_token` is not reusable for navigation** — the
`:embedded` hook assigns `session_token: nil` (Shopify's `id_token` lives
~60s and App Bridge doesn't reissue one on a client-side `navigate`); use a
plain `<.link navigate={...}>` between LiveViews in the same `live_session`,
the same as the template links above. Wire it up with a plain `live_session`:

```elixir
scope "/", MyAppWeb do
  pipe_through [:shopifex_browser, :shopify_session]

  live_session :embedded,
    session: {ShopifexWeb.LiveSession, :put_shop_in_session, []},
    on_mount: [{ShopifexWeb.LiveSession, :embedded}],
    layout: {MyAppWeb.Layouts, :embedded} do
    live "/", MyAppLive
    ...
  end
end
```

`ShopifexWeb.Routes.shopifex_live_session/3` is the 2.x-compatible macro: it
uses the default `:assign_shop_to_socket` hook, which assigns `@current_shop`
and `@session_token` without redirecting when no shop is in the session.

## Update app permissions

With managed installation, **change your access scopes in `shopify.app.toml`**
(`[access_scopes]`) and deploy your app config — Shopify grants the updated
scopes when the merchant next opens the app. Update `config :shopifex, :scopes`
to match. Both the config value and the shop's stored `scope` are normalised
with `Shopifex.Scopes.split/1` before they are compared: whitespace around
scope names is ignored and empty segments are dropped, so
`"read_products, write_products"` matches Shopify's
`"read_products,write_products"` grant, and an empty or `nil` `:scopes` config
requires nothing from `Shopifex.Plug.EnsureScopes`. On the next embedded load, `:managed_install` sees that the shop's
stored `scope` lacks a configured scope and re-exchanges the `id_token`, which
persists Shopify's current grant. If the grant is still short (the merchant has
not approved the new scopes), `Shopifex.Plug.EnsureScopes` **raises** an
actionable error by default, so config drift surfaces immediately rather than
silently bouncing the merchant through OAuth.

> **Legacy OAuth scope update (compatibility only).** If you opt into the OAuth
> fallback (`plug Shopifex.Plug.EnsureScopes, on_missing_scopes: :redirect`), add
> `your-redirect-url.com/auth/update` to Shopify's whitelist and redirect the
> merchant to re-authorize:
>
> ```
> https://{shop-name}.myshopify.com/admin/oauth/request_grant?client_id=API_KEY&redirect_uri={YOUR_REINSTALL_URL}/auth/update&scope={YOUR_SCOPES},read_customers
> ```

## Add payment guards to routes
This system allows you to use the `Shopifex.Plug.PaymentGuard` plug. If the merchant does not have an active grant associated with the named guard, it will redirect them to a plan selection page, allow them to pay, and handle the payment callback all automatically. I am working on the admin panel where you can register Plan objects which grant `premium_plan` (for example) - but for now these need to be entered manually into the database.

Generate the schemas

`mix phx.gen.schema Shops.Plan plans name:string price:string features:array:string grants:array:string test:boolean trial_days:integer usages:integer type:string`

`mix phx.gen.schema Shops.Grant grants shop_id:references:shops charge_id:bigint grants:array:string remaining_usages:integer total_usages:integer`

`usages` (Plan) and `remaining_usages`/`charge_id` (Grant) should be nullable —
unlimited plans have no usage cap, and `create_shop_grant/2` never supplies a
`charge_id`. Shopify charge ids exceed Postgres's `int4` range, hence
`charge_id:bigint` rather than `:integer`. (`mix shopifex.install` generates
both schemas with this nullability for you.)

Add the config options:
```elixir
config :shopifex,
  payment_guard: MyApp.Shops.PaymentGuard,
  grant_schema: MyApp.Shops.Grant,
  plan_schema: MyApp.Shops.Plan,
  payment_redirect_uri: "https://myapp.ngrok.io/payment/complete"
```
> The plan-selection page renders with Polaris web components loaded from
> Shopify's CDN, so there are no Shopifex static assets to serve (the old
> `Plug.Static, at: "/shopifex-assets"` step is no longer needed as of 3.0).

Create the payment guard module:
```elixir
defmodule MyApp.Shops.PaymentGuard do
  use Shopifex.PaymentGuard
end
```
Create a new payment controller:
```elixir
defmodule MyAppWeb.PaymentController do
  use MyAppWeb, :controller
  use ShopifexWeb.PaymentController
end
```
Add payment routes to `router.ex`:
```elixir
ShopifexWeb.Routes.payment_routes(MyAppWeb.PaymentController)
```

> **Custom select-plan actions.** The standard `select_plan/2` action calls
> `create_charge/2` and then cryptographically binds the pending charge with
> `ShopifexWeb.PaymentController.bind_charge/4` before redirecting to Shopify's
> confirmation URL. If your app defines its own action to initiate charges
> instead of using `select_plan/2`, it **must** call `bind_charge/4` itself —
> `complete_payment/2` rejects a charge with no signed binding. Override
> `create_charge/2` / `verify_charge/3` (both public, overridable callbacks on
> `ShopifexWeb.PaymentController`) to customise how a charge is created and how
> its status is verified with Shopify.

> ⚠️ **Multi-node deploys (Fly.io, etc.):** use `Shopifex.RedirectAfter.Ecto`, not
> the in-memory default. The billing flow stores a `charge_id → redirect_after`
> entry at `/payment/select-plan` and reads it back at `/payment/complete`. The
> default `Shopifex.RedirectAfterAgent` keeps that in a **node-local** `Agent`, so
> when Shopify's confirmation returns to a *different* node the lookup misses —
> `complete_payment/2` responds `403` (a `Plug.Conn`, logged at `:error`) **and
> the grant is never created** (the merchant is still charged). The shipped, DB-backed
> `Shopifex.RedirectAfter.Ecto` is safe across nodes:
>
> ```elixir
> config :shopifex, :redirect_after_agent, Shopifex.RedirectAfter.Ecto
> ```
>
> Add its backing table (`mix shopifex.install` generates both the config and this
> migration for new apps):
>
> ```elixir
> create table(:shopifex_charge_redirects, primary_key: false) do
>   add :charge_id, :bigint, primary_key: true
>   add :redirect_after, :text, null: false
>   add :inserted_at, :utc_datetime, null: false
> end
> ```
>
> On a single node the in-memory default is fine. Either way, a missed lookup now
> logs an actionable `Logger.error` instead of failing silently.

To manage plans, I recommend using [kaffy admin package](https://github.com/aesmail/kaffy)

Now you can protect routes or controller actions with the `Shopifex.Plug.PaymentGuard` plug. Here is an example of it in action on an admin link
```elixir
defmodule MyAppWeb.AdminLinkController do
  use MyAppWeb, :controller
  require Logger

  plug Shopifex.Plug.PaymentGuard, "premium_plan" when action in [:premium_function]
  
  def premium_function(conn, _params) do
    shop = Shopifex.Plug.current_shop(conn)
    
    # Wow, much premium.
    conn
    |> send_resp(200, "Hi there, #{shop.url}!")
  end
end
```
### Single Page Applications
SPA Shopify applications are also supported with Shopifex for developers who wish to host their front-end application separately from the back-end. This approach takes advantage of [Shopify session tokens](https://shopify.dev/concepts/apps/building-embedded-apps-using-session-tokens).

Adjust your `router.ex` file. You may notice some routes are no longer necessary compared to the quick-start guide.
```elixir
ShopifexWeb.Routes.pipelines()

# These routes will take care of installation/update
ShopifexWeb.Routes.auth_routes(ShopifyAppWeb)

# API routes for your SPA to hit with the axios instance
scope "/api", MyAppWeb do
  pipe_through [:shopify_api]
  
  # An endpoint which your SPA can call on load to get whatever initialization data your app needs.
  # The options macro is required to allow CORS requests on the route.
  options "/initialize", AuthController, :initialize
  get "/initialize", AuthController, :initialize
  
  # Add authenticated routes here as needed.
end
```
And for that `/initialize` endpoint, consider this adjustment to `MyAppWeb.AuthController` and update based on your needs. Perhaps you also want to serialize and return some more information needed by your SPA at startup.
```elixir
defmodule MyAppWeb.AuthController do
  use MyAppWeb, :controller
  use ShopifexWeb.AuthController
  
  def initialize(conn, _params) do
    # Guardian is no longer used — the `:shopify_api` pipeline verifies the
    # App Bridge session token and loads the shop.
    shop = Shopifex.Plug.current_shop(conn)

    render(conn, "initialize.json", %{shop: shop})
  end
end
```
Load [App Bridge](https://shopify.dev/docs/api/app-bridge-library) from Shopify's
CDN with your API key in a meta tag. App Bridge auto-initializes and exposes a
global `shopify` object, and automatically attaches a fresh session token as the
`Authorization: Bearer` header on same-origin `fetch` calls — which is exactly
what the `:shopify_api` pipeline (`Shopifex.Plug.ShopifyApiAuth`) verifies.

```html
<meta name="shopify-api-key" content="MY_SHOPIFY_API_KEY" />
<script src="https://cdn.shopify.com/shopifycloud/app-bridge.js"></script>
```
```javascript
// App Bridge attaches the Bearer token automatically — no axios interceptor needed.
const res = await fetch('/api/initialize');
const sessionData = await res.json();

// If you need the raw token (e.g. for a WebSocket), ask App Bridge for one:
const token = await shopify.idToken();
```

> The old `import createApp from '@shopify/app-bridge'` / `createApp({ apiKey, shopOrigin })`
> flow (and the axios session-token tutorial) is the deprecated App Bridge v2/v3 API
> and no longer applies — the CDN App Bridge above is the current path.
