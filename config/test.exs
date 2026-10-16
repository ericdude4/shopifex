import Config

config :shopifex,
  shop_schema: %{},
  payment_guard: Shopifex.Plug.PaymentGuardTest.PaymentGuard,
  env: Mix.env()

# Route Shopifex.Auth / Shopifex.API HTTP through Req.Test so token-lifecycle
# and GraphQL transport can be tested without real Shopify calls. Each test
# registers a stub against the `Shopifex.ReqStub` name.
#
# `retry_delay: 0` collapses the backoff on the refresh retry so the suite
# doesn't sleep through it. Because :req_options is appended after the
# library's own Req options, this also demonstrates that a host app can
# override any of them.
config :shopifex, :req_options, plug: {Req.Test, Shopifex.ReqStub}, retry_delay: 0

import_config "../test/support/shopifex_dummy/config/config.exs"
