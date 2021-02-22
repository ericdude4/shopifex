use Mix.Config

config :shopifex,
  shop_schema: %{},
  payment_guard: Shopifex.Plug.PaymentGuardTest.PaymentGuard,
  env: Mix.env()

import_config "../test/support/shopifex_dummy/config/config.exs"
