defmodule Shopifex.Plug.ValidateHmac do
  @moduledoc """
  Ensures that the current request contains a valid HMAC
  token.
  """
  import Plug.Conn
  require Logger

  def init(options) do
    # initialize options
    options
  end

  def call(conn, _) do
    expected_hmac = Shopifex.Plug.build_hmac(conn)
    received_hmac = Shopifex.Plug.get_hmac(conn)

    if expected_hmac == received_hmac do
      conn
    else
      Logger.info("HMAC doesn't match " <> expected_hmac)

      conn
      |> send_resp(401, "invalid hmac signature")
      |> halt()
    end
  end
end
