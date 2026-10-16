defmodule Shopifex.Plug.ValidateHmac do
  @moduledoc """
  Ensures the current request carries a valid Shopify query / app-proxy HMAC
  signature and, when present, a fresh `timestamp`.

  Security properties:

    * HMACs are compared in constant time with `Plug.Crypto.secure_compare/2`.
    * Computed HMAC values are never logged.
    * When the request includes a `timestamp` parameter (Shopify always sends one
      for admin-load and app-proxy flows) it must be within
      `config :shopifex, :hmac_timestamp_tolerance_seconds` (default `90`) of now,
      closing the replay window. (A request that carries no `timestamp` skips the
      freshness check, unless `:require_timestamp` is set — see below.)

  ## Requiring a timestamp

  Some signed flows (e.g. bulk-action links) legitimately omit `timestamp`, so by
  default a missing timestamp is allowed. App-proxy requests, however, *always*
  carry one, and without it the signed URL is replayable forever. Pass
  `require_timestamp: true` to reject any request that lacks a `timestamp`:

      plug Shopifex.Plug.ValidateHmac, require_timestamp: true

  The `:shopify_proxy` pipeline sets this by default.

  ## Per-pipeline tolerance

  The `config :shopifex, :hmac_timestamp_tolerance_seconds` default is global. App
  proxy / storefront requests can legitimately lag past 90s, but widening the
  global value also widens the admin-load replay window. Pass a `plug` option to
  relax the tolerance for one pipeline only, without touching the global default:

      plug Shopifex.Plug.ValidateHmac, timestamp_tolerance_seconds: 600

  This plug **only verifies the signature** — it does not load the shop into
  `conn.assigns`. The `:shopify_proxy` pipeline pairs it with
  `Shopifex.Plug.LoadProxyShop` so app-proxy consumers get `current_shop/1`.
  """
  import Plug.Conn
  require Logger

  def init(options), do: options

  def call(conn, options) do
    with :ok <- Shopifex.Plug.validate_timestamp(conn, options),
         :ok <- validate_signature(conn) do
      conn
    else
      {:error, reason} ->
        # Log the failure category only — never the expected/received HMAC.
        Logger.info("Rejecting request with invalid HMAC (#{reason})")

        conn
        |> send_resp(401, "invalid hmac signature")
        |> halt()
    end
  end

  defp validate_signature(conn) do
    if Shopifex.Plug.hmac_matches?(conn, Shopifex.Plug.get_hmac(conn)) do
      :ok
    else
      {:error, "signature mismatch"}
    end
  end
end
