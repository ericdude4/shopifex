use Mix.Config

config :shopifex,
  shop_schema: %{},
  payment_guard: Shopifex.Plug.PaymentGuardTest.PaymentGuard

config :shopifex,
  ecto_repos: [Shopifex.Repo]
