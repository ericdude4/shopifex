defmodule ShopifexDummy.Repo do
  use Ecto.Repo,
    otp_app: :shopifex,
    adapter: Ecto.Adapters.Postgres
end
