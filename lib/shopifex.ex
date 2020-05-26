defmodule Shopifex do
  @moduledoc """
  # Welcome to Shopifex! All configuration options are required

  ## Configuration
  * `:app_name` - This gets used in the Shopifex provided app installation page
  * `:repo` - The Ecto.Repo for your application
  * `:shop_schema` - Your Ecto.Schema that must have :url, :scopes, and :access_token properties. This is used to install and load stores into the session
  * `:redirect_uri` - The redirect URI used in the Shopify app installation process. Must be whitelisted in your Shopify app configuration
  * `:api_key` - Your Shopify app's API key
  * `:secret` - Your Shopify app's secret
  * `scopes` - Shopify OAuth scopes which your application requires
  * `:webhook_uri` - When webhooks are created by Shopifex, this is used as the webhook endpoint
  * `:webhook_topics` - Topics to subscribe to after installation is complete

  Example:

  ```
  config :shopifex,
    app_name: "MyApp",
    repo: MyApp.Repo,
    shop_schema: MyApp.Shop,
    api_key: "shopifyapikey123",
    secret: "shopifyapisecret456",
    redirect_uri: "https://myapp.ngrok.io/auth/install",
    scopes: "read_inventory,write_inventory,read_products,write_products,read_orders",
    webhook_uri: "https://myapp.ngrok.io/webhook",
    webhook_topics: ["app/uninstalled"]
  ```
  """
end
