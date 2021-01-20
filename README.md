# Shopifex

A simple boilerplate package for creating Shopify embedded apps with the Elixir Phoenix framework. [https://hexdocs.pm/shopifex](https://hexdocs.pm/shopifex)

For from-scratch setup instructions (slightly out of date), read [Create and Elixir Phoenix Shopify App in 5 Minutes](https://medium.com/@ericdude4/create-an-elixir-phoenix-shopify-app-in-5-minutes-ca308bc42216)

## Installation

The package can be installed
by adding `shopifex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:shopifex, "~> 0.3"}
  ]
end
```
## Quickstart

Add the `:shopifex` config settings to your `config.ex`. More config details [here](https://hexdocs.pm/shopifex)

```elixir
config :shopifex,
  app_name: "MyApp",
  shop_schema: MyApp.Shop,
  web_module: MyAppWeb,
  repo: MyApp.Repo,
  path_prefix: "/shopfy-app", # optional, default is "" (empty string). This is useful for umbrella apps scoped by a reverse proxy
  redirect_uri: "https://myapp.ngrok.io/auth/install",
  reinstall_uri: "https://myapp.ngrok.io/auth/update",
  webhook_uri: "https://myapp.ngrok.io/webhook",
  scopes: "read_inventory,write_inventory,read_products,write_products,read_orders",
  api_key: "shopifyapikey123",
  secret: "shopifyapisecret456",
  webhook_topics: ["app/uninstalled"] # These are automatically subscribed on a store upon install
```

Update your `endpoint.ex` to include the custom body parser. This is necessary for HMAC validation to work.

```elixir
@session_options [
  store: :cookie,
  key: "_my_app_key",
  signing_salt: "Es1PzgRs",
  secure: true, # <- add this
  extra: "SameSite=None" # <- add this
]
# ...
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  body_reader: {ShopifexWeb.CacheBodyReader, :read_body, []},
  json_decoder: Phoenix.json_library()
```

Add this line near the top of `router.ex` to include the Shopifex pipelines

```elixir
ShopifexWeb.Routes.pipelines()
```
Now the following pipelines are accessible:

- `:shopify_browser` -> Calls custom Shopifex fetch_flash amd removes iframe blocking headers as well as standard :browser pipeline stuff
- `:shopify_session` -> Ensures that a valid store is currently loaded in the session and is accessible in your controllers/templates as `conn.private.shop`
- `:shopify_entrypoint` -> Validates HMAC parameters to make sure the incoming requests from Shopify are valid. For example, when the app is being installed, or the initial loading of your App inside of the Shopify admin panel.
- `:shopify_webhook` -> Validates webhook request HMAC and makes shop accessible in your controllers/templates as `conn.private.shop`
- `:admin_links` -> fetches flash and removes iframe headers. Useful for admin link endpoints

Now add this basic example of these plugs in action in `router.ex`. These endpoints need to be added to your Shopify app whitelist

```elixir
# Include all auth (when Shopify requests to render your app in an iframe), installation and update routes 
ShopifexWeb.Routes.auth_routes(MyAppWeb)

# Place your in-shopify-session endpoints in here
scope "/", MyAppWeb do
  pipe_through [:shopify_browser, :shopify_session]

  get "/", PageController, :index
end

# Make your webhook endpoint look like this
scope "/webhook", MyAppWeb do
  pipe_through [:shopify_webhook]

  post "/", WebhookController, :action
end

# Place your admin link endpoints in here
scope "/admin-links", MyAppWeb do
  pipe_through [:admin_links, :shopify_webhook]

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
  def after_install(conn, shop) do
    # TODO: send yourself an e-mail
    # follow default behaviour.
    super(conn, shop)
  end
end
```

create another controller called `webhook_controller.ex` to handle incoming Shopify webhooks

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
    Shopifex.Shops.delete_shop(shop)

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
## Update app permissions

You can also update the app permissions after installation. To do so, first you have to add `your-redirect-url.com/auth/update` to Shopify's whitelist.

To add e.g. the `read_customers` scope, you can do so by redirecting them to the following example url:

```
https://{shop-name}.myshopify.com/admin/oauth/request_grant?client_id=API_KEY&redirect_uri={YOUR_REINSTALL_URL}/auth/update&scope={YOUR_SCOPES},read_customers
```

## Beta feature: Add payment guards to routes
This system allows you to use the `Shopifex.Plug.PaymentGuard` plug. If the merchant does not have an active grant associated with the named guard, it will redirect them to a plan selection page, allow them to pay, and handle the payment callback all automatically.

Generate the schemas

`mix phx.gen.html Shops Plan plans name:string price:string features:array grants:array test:boolean`

`mix phx.gen.html Shops Grant grants shop:references:shops charge_id:integer grants:array`

Add the config options:
```elixir
config :my_app,
  payment_guard: MyApp.Shops.PaymentGuard,
  grant_schema: MyApp.Shops.Grant,
  plan_schema: MyApp.Shops.Plan
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
ShopifexWeb.Routes.payment_routes(MyAppWeb)
```
To manage plans, add admin routes behind a secure scope. Here you can manage available payment options (layout ugly, work in progress).
```elixir
# I used Pow, but you can use whatever you like
pipeline :protected do
  plug Pow.Plug.RequireAuthenticated,
    error_handler: Pow.Phoenix.PlugErrorHandler
end

scope "/admin" do
  pipe_through [:protected]
  MyAppWeb.Routes.shopifex_admin()
end

# This is Pow-specific. It registers the routes for logging in
scope "/" do
  pipe_through :shopify_browser

  pow_routes()
end
```
Now you can protect routes or controller actions with the `Shopifex.Plug.PaymentGuard` plug. Here is an example of it in action on an admin link
```elixir
defmodule MyAppWeb.AdminLinkController do
  use MyAppWeb, :controller
  require Logger

  plug Shopifex.Plug.PaymentGuard, "premium_plan" when action in [:premium_function]
  
  def premium_function(conn, _params) do
    # Wow, much premium.
    conn
    |> send_resp(200, "success")
  end
end
```
