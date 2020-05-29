# Shopifex

A simple boilerplate package for creating Shopify embedded apps with the Elixir Phoenix framework. [https://hexdocs.pm/shopifex](https://hexdocs.pm/shopifex)

## Installation

The package can be installed
by adding `shopifex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:shopifex, "~> 0.1.1"}
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
  redirect_uri: "https://myapp.ngrok.io/auth/install",
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
# Make sure the app can load inside of an iFrame
pipeline :browser do
  ...
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

Now add this basic example of these plugs in action in `router.ex`

```elixir
scope "/auth", MyAppWeb do
  pipe_through [:browser, :shopify_entrypoint]
  get "/", AuthController, :auth
  get "/install", AuthController, :install
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
end
```
