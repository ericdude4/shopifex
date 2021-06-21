use Mix.Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :shopifex, ShopifexDummy.Repo,
  username: "postgres",
  password: "postgres",
  database: "shopifex_dummy_test#{System.get_env("MIX_TEST_PARTITION")}",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :shopifex, ShopifexDummyWeb.Endpoint,
  http: [port: 4002],
  server: false

config :shopifex,
  app_name: "Shopifex Dummy",
  shop_schema: ShopifexDummy.Shop,
  payment_guard: ShopifexDummy.Shops.PaymentGuard,
  grant_schema: ShopifexDummy.Shops.Grant,
  plan_schema: ShopifexDummy.Shops.Plan,
  repo: ShopifexDummy.Repo,
  web_module: ShopifexDummyWeb,
  scopes: "read_inventory",
  webhook_topics: ["app/uninstalled", "orders/create", "carts/update"],
  payment_redirect_uri: "https://shopifex-dummy.com/payment/complete",
  redirect_uri: "https://shopifex-dummy.com/auth/install",
  reinstall_uri: "https://shopifex-dummy.com/auth/update",
  webhook_uri: "https://shopifex-dummy.com/webhook",
  api_key: "thisisafakeapikey",
  secret: "shpss_thisisafakesecret"

# Print only warnings and errors during test
config :logger, level: :warn
