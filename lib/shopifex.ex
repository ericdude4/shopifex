defmodule Shopifex do
  @moduledoc """
  A simple boilerplate package for creating Shopify embedded apps with the Elixir Phoenix framework. [https://hexdocs.pm/shopifex](https://hexdocs.pm/shopifex)

  ## Installation

  The package can be installed
  by adding `shopifex` to your list of dependencies in `mix.exs`:

  ```elixir
  def deps do
  [
    {:shopifex, "~> 2.1"}
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

  """
end
