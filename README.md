<img width="350" src="https://github.com/ericdude4/shopifex/raw/master/guides/images/logo.png" alt="Shopifex">

---

[![Hex.pm](https://img.shields.io/hexpm/v/shopifex.svg)](https://hex.pm/packages/shopifex)

A simple boilerplate package for creating Shopify embedded apps with the Elixir Phoenix framework. [https://hexdocs.pm/shopifex](https://hexdocs.pm/shopifex)

## Installation

The package can be installed
by adding `shopifex` to your list of dependencies in `mix.exs`: (note, OTP 22 or greater required)

```elixir
def deps do
  [
    {:shopifex, "~> 2.2"}
  ]
end
```
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
Replace tunnel-url with your own where applicable.
- Set "App URL" to `https://my-app.ngrok.io/auth`
- Add `https://my-app.ngrok.io/auth/install` & `https://my-app.ngrok.io/auth/update` to your app's "Allowed redirection URL(s)"
- Add your Shopify app's API key and API secret key to `config :shopifex, api_key: "your-api-key", secret: "your-api-secret"`

## Manual Installation
Create the shop schema where the installation data will be stored:
```
mix phx.gen.schema Shop shops url:string access_token:string scope:string
mix ecto.migrate
```

Add the `:shopifex` config settings to your `config.ex`. More config details [here](https://hexdocs.pm/shopifex)

```elixir
config :shopifex,
  app_name: "MyApp",
  shop_schema: MyApp.Shop,
  web_module: MyAppWeb,
  repo: MyApp.Repo,
  redirect_uri: "https://myapp.ngrok.io/auth/install",
  reinstall_uri: "https://myapp.ngrok.io/auth/update",
  webhook_uri: "https://myapp.ngrok.io/webhook",
  scopes: "read_inventory,write_inventory,read_products,write_products,read_orders",
  api_key: "shopifyapikey123",
  secret: "shopifyapisecret456",
  webhook_topics: ["app/uninstalled"], # These are automatically subscribed on a store upon install
  allowed_drift: 10_000 # session token exp/nbf tolerance in ms (defaults to 10s)
```

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

- `:shopify_session` -> Validates request (HMAC header/param or token param) and makes session information available via `Shopifex.Plug` API. Also removes iFrame blocking headers so app can render in Shopify admin.
- `:shopify_webhook` -> Validates Shopify webhook requests HMAC and makes session information available via `Shopifex.Plug` API.
- `:shopify_admin_link` -> Validates Shopify admin link & bulk action link requests and makes session information available via `Shopifex.Plug` API.
- `:shopify_api` -> Ensures that a valid Shopify session token or Shopifex token are present in `Authorization` header. Useful for async requests between your SPA front end and Shopifex backend.
- `:shopifex_browser` -> Same as your normal `:browser` pipeline, except it calls `Shopifex.Plug.LoadInIframe`.  Deprecated; does not work with Phoenix 1.6 generated apps.

Now add this basic example of these plugs in action in `router.ex`. These endpoints need to be added to your Shopify app whitelist

### Routing
```elixir
# Include all auth (when Shopify requests to render your app in an iframe), installation and update routes 
ShopifexWeb.Routes.auth_routes(MyAppWeb.AuthController)

# Add the LoadInIframe plug to your existing :browser pipeline
pipeline :browser do
  # ... Other plugs
  plug Shopifex.Plug.LoadInIframe
end

# Endpoints accessible within the Shopify admin panel iFrame.
# Don't include this scope block if you are creating a SPA.
scope "/", MyAppWeb do
  pipe_through [:browser, :shopify_session]

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
As browsers continue to restrict cookies, cookies become more unreliable as a method for maintaining a session within an iFrame. To address this, Shopify recommends passing a JWT session token back and forth between requests.

Shopifex makes a token accessible with `Shopifex.Plug.session_token(conn)` in any request which passes through a `:shopify_*` router pipeline.

Ensure there is a `token` parameter sent along in any requests which you would like to maintain session between.

EEx template link:
```elixir
<%= link "home", to: Routes.page_path(@conn, :index, %{token: Shopifex.Plug.session_token(conn)}) %>
```
EEx template form:
```elixir
<%= form_for :foo, Routes.foo_path(MyApp.Endpoint, :new, %{token: Shopifex.Plug.session_token(@conn)}), fn f -> %>
  <%= submit "Submit" %>
<% end %>
```

## Using LiveView in your embedded app
There are two special considerations to using LiveView in your embedded app.

First, you'll need to get the LiveView socket configured to work in the Shopify iframe. This [elixir](https://elixirforum.com/t/how-to-embed-a-liveview-via-iframe/65066) post gives some excellent tips.

Second, you'll need to copy the `current_shop` and `session_token` from the Plug connection to the socket and make them available in your assigns on_mount. The `@current_shop` will be your authenticated Shop resource, and `@session_token` can be used when you navigate between live views similar to the template links above.  The `shopifex_live_session` macro is a drop-in replacement fom `live_session` to handle this.

```
scope "/", ShoplensWeb do
  pipe_through [:shopifex_browser, :shopify_session]

  ShopifexWeb.Routes.shopifex_live_session :embedded, layout: {MyApp.Layouts, :embedded} do
    live "/", MyAppLive
    ...
  end

  # If you need more control, you can still use `live_session` like this:
  #  live_session :embedded, 
  #    session: {ShopifexWeb.LiveSession, :put_shop_in_session, []}, 
  #    on_mount: {ShopifexWeb.LiveSession, :assign_shop_to_socket} do
  #       ...
  #   end
end
```

## Update app permissions

You can also update the app permissions after installation. To do so, first you have to add `your-redirect-url.com/auth/update` to Shopify's whitelist.

To add e.g. the `read_customers` scope, you can do so by redirecting them to the following example url:

```
https://{shop-name}.myshopify.com/admin/oauth/request_grant?client_id=API_KEY&redirect_uri={YOUR_REINSTALL_URL}/auth/update&scope={YOUR_SCOPES},read_customers
```

## Add payment guards to routes
This system allows you to use the `Shopifex.Plug.PaymentGuard` plug. If the merchant does not have an active grant associated with the named guard, it will redirect them to a plan selection page, allow them to pay, and handle the payment callback all automatically. I am working on the admin panel where you can register Plan objects which grant `premium_plan` (for example) - but for now these need to be entered manually into the database.

Generate the schemas

`mix phx.gen.schema Shops.Plan plans name:string price:string features:array:string grants:array:string test:boolean usages:integer type:string`

`mix phx.gen.schema Shops.Grant grants shop_id:references:shops charge_id:integer grants:array:string remaining_usages:integer total_usages:integer`

Add the config options:
```elixir
config :my_app,
  payment_guard: MyApp.Shops.PaymentGuard,
  grant_schema: MyApp.Shops.Grant,
  plan_schema: MyApp.Shops.Plan,
  payment_redirect_uri: "https://myapp.ngrok.io/payment/complete"
```
Serve the Shopifex assets for the plans selection page. Add the following to `endpoint.ex`:
```elixir
# Serve at "/shopifex-assets" the static files from shopifex.
plug Plug.Static,
  at: "/shopifex-assets",
  from: :shopifex,
  gzip: false,
  only: ~w(css fonts images js favicon.ico robots.txt)
```
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
    shop = Guardian.Plug.current_resource(conn)
    
    render(conn, "initialize.json", %{shop: shop})
  end
end
```
Now, [integrate Shopify session tokens into the Axios instance of your SPA.](https://shopify.dev/tutorials/use-session-tokens-with-axios)
Then from your SPA:
```javascript
import createApp from '@shopify/app-bridge';
// Import your Shopify session_token axios instance based on the Shopify session token axios instructions
import instance from './axios-instance';

const urlParams = new URLSearchParams(window.location.search);
const shopOrigin = urlParams.get('shop');

window.app = createApp({
  apiKey: "MY_SHOPIFY_API_KEY",
  shopOrigin,
});

// Use your axios instance to call the /api/initialize endpoint
const sessionData = await instance.get('/api/initialize');
// Now you will have access to the current shop and Bob's-yer-uncle!
```

## Using Shopifex with Shopify CLI

Use the Shopify CLI to simplify the setup process and avoid manual configuration of URLs and environment variables.

For more details on using the Shopify CLI, refer to the [Shopify CLI documentation](https://shopify.dev/docs/api/shopify-cli).

### Folder Structure

Your project structure should look something like this:

```md
- phx/       # Phoenix app
- shopify/   # Shopify cli (`shopify app init`) generated contents
```

### Shopify CLI Configuration

1. Modify the existing `shopify.app.toml` file in the `shopify/` folder to include the following configuration. This ensures that Cloudflare tunnels are automatically updated during development:

```toml
[build]
automatically_update_urls_on_dev = true
```

2. Create a `shopify.web.toml` file in the `shopify/web/` folder. This ensures that the Shopify CLI starts your Phoenix app when running `shopify app dev`.

```toml
name = "phx"
roles = ["backend", "frontend"]
port = 4000

webhooks_path = "/shopify/webhooks"

[commands]
dev = "./start.sh"
```

3. Add the following `start.sh` script to the `shopify/web/` folder to start your Phoenix server:

```bash
#!/bin/bash

# Navigate to the phoenix directory
cd ./../phx

# Available environment variables
# https://shopify.dev/docs/apps/build/cli-for-apps/migrate-to-latest-cli#provided-variables
echo "[start.sh] Served from: '$HOST'"
echo "[start.sh] Enabled API scopes: '$SCOPES'"

# Start the Phoenix server
mix phx.server
```

### Configuring Phoenix with Shopify CLI

The Shopify CLI sets certain environment variables that can be used to configure your Phoenix app dynamically. Update your `runtime.exs` file to use these variables:

```elixir
# filepath: phx/config/runtime.exs
import Config

if config_env() != :test do
  shopify_api_key = System.get_env("SHOPIFY_API_KEY")
  shopify_api_secret = System.get_env("SHOPIFY_API_SECRET")
  shopify_api_scopes = System.get_env("SCOPES")

  confs = %{
    "SHOPIFY_API_KEY" => shopify_api_key,
    "SHOPIFY_API_SECRET" => shopify_api_secret,
    "SCOPES" => shopify_api_scopes
  }

  for {conf_key, conf_value} <- confs do
    if is_nil(conf_value) do
      Logger.warning("""
      environment variable #{conf_key} is missing.
      In development this is automatically set when running `shopify app dev`
      """)
    end
  end

  config :shopifex,
    api_key: shopify_api_key,
    secret: shopify_api_secret,
    scopes: shopify_api_scopes
end

if host = System.get_env("HOST") do
  # Support proxy URLs `HOST` is set by the Shopify CLI when running the dev command
  {:ok, host_uri} = URI.new(host)

  config :shopifex,
    redirect_uri: host_uri |> URI.append_path("/auth/callback") |> URI.to_string(),
    reinstall_uri: host_uri |> URI.append_path("/auth/calback") |> URI.to_string(),
    webhook_uri: host_uri |> URI.append_path("/shopify/webhooks") |> URI.to_string(),
    payment_redirect_uri: host_uri |> URI.append_path("/shopify/payments") |> URI.to_string()
end
```

### Starting the Development Environment

1. Navigate to the `shopify/` folder.
2. Run the following command to start the Shopify development environment:

```sh
shopify app dev
```

This command will:

- Set up a Cloudflare proxy for your app
- Set environment variables required for your app
- Start your Phoenix server
