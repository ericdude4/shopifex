defmodule ShopifexDummyWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :shopifex

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_shopifex_key",
    signing_salt: "qb1yL9WE"
  ]

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    body_reader: {ShopifexWeb.CacheBodyReader, :read_body, []},
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(ShopifexDummyWeb.Router)
end
