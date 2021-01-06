# Shopifex

A simple boilerplate package for creating Shopify embedded apps with the Elixir Phoenix framework. [https://hexdocs.pm/shopifex](https://hexdocs.pm/shopifex)

For from-scratch setup instructions, read [Create and Elixir Phoenix Shopify App in 5 Minutes](https://medium.com/@ericdude4/create-an-elixir-phoenix-shopify-app-in-5-minutes-ca308bc42216)

## Installation

The package can be installed
by adding `shopifex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:shopifex, "~> 0.2.0"}
  ]
end
```
## Quickstart

Add the `:shopifex` config settings to your `config.ex`. More config details [here](https://hexdocs.pm/shopifex)

```elixir
config :shopifex,
  app_name: "MyApp",
  shop_schema: MyApp.Shop,
  repo: MyApp.Repo,
  app_uri: "/auth", # optional, default is "/auth"
  redirect_uri: "https://myapp.ngrok.io/auth/install",
  reinstall_uri: "https://myapp.ngrok.io/auth/update",
  webhook_uri: "https://myapp.ngrok.io/webhook",
  scopes: "read_inventory,write_inventory,read_products,write_products,read_orders",
  api_key: "shopifyapikey123",
  secret: "shopifyapisecret456",
  webhook_topics: ["app/uninstalled"]
```

Update your `endpoint.ex` to include the custom body parser. This is necessary for HMAC validation to work.

```elixir
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  body_reader: {ShopifexWeb.CacheBodyReader, :read_body, []},
  json_decoder: Phoenix.json_library()
```

Update your `router.ex` to include the Shopifex plugs

```elixir
# Make your browser pipeline look like this
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug Shopifex.Plug.FetchFlash
  plug :protect_from_forgery
  plug :put_secure_browser_headers
  plug Shopifex.Plug.LoadInIframe
end

# Ensures that a valid store is currently loaded in the session and is accessible in your controllers/templates as `conn.private.shop`
pipeline :shopify_session do
  plug Shopifex.Plug.ShopifySession
end

# Make sure the incoming requests from Shopify are valid. For example, when the app is being installed, or the initial loading of your App inside of the Shopify admin panel.
pipeline :shopify_entrypoint do
  plug Shopifex.Plug.ShopifyEntrypoint
end

# Ensures that the connection has a valid Shopify webhook HMAC token
pipeline :shopify_webhook do
  plug Shopifex.Plug.ShopifyWebhook
end
```

Now add this basic example of these plugs in action in `router.ex`. These endpoints need to be added to your Shopify app whitelist

```elixir
scope "/auth", MyAppWeb do
  pipe_through [:browser, :shopify_entrypoint]
  get "/", AuthController, :auth
  get "/install", AuthController, :install
  get "/update", AuthController, :update
end

scope "/", MyAppWeb do
  pipe_through [:browser, :shopify_session]

  get "/", PageController, :index
end

scope "/webhook", MyAppWeb do
  pipe_through [:shopify_webhook]

  post "/", WebhookController, :action
end
```

Create a new controller called `auth_controller.ex` to handle the initial iFrame load and installation

```elixir
defmodule MyAppWeb.AuthController do
  use MyAppWeb, :controller
  use ShopifexWeb.AuthController

  # Thats it! Validation, installation are now handled for you :)
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

Then add the following route to your `/auth` scope:

```
scope "/auth", MyAppWeb do
  ...
  get "/update", AuthController, :update
end
```

To add e.g. the `read_customers` scope, you can do so by redirecting them to the following example url:

```
https://{shop-name}.myshopify.com/admin/oauth/request_grant?client_id=API_KEY&redirect_uri={YOUR_REINSTALL_URL}/auth/update&scope={YOUR_SCOPES},read_customers
```