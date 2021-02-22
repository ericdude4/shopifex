# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :shopifex,
  ecto_repos: [ShopifexDummy.Repo]

# Configures the endpoint
config :shopifex, ShopifexDummyWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "AJifLO3O2O9g5ZbqKyGNPEklxuNA8BIIqXTWYU+wxgdTEvzjHbz1FUj0scAX647D",
  render_errors: [view: ShopifexDummyWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: ShopifexDummy.PubSub,
  live_view: [signing_salt: "PSZGj+FT"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
