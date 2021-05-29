defmodule Shopifex.Plug.PaymentGuard do
  require Logger

  def init(options) do
    # initialize options
    options
  end

  @doc """
  This makes sure the shop in the session contains a payment which unlocks the guard
  """
  def call(conn, guard_identifier) do
    payment_guard = Application.fetch_env!(:shopifex, :payment_guard)

    shop = Shopifex.Plug.current_shop(conn)

    case payment_guard.grant_for_guard(shop, guard_identifier) do
      nil ->
        Logger.info("Payment guard blocked request")
        redirect_after = URI.encode_www_form("#{conn.request_path}?#{conn.query_string}")

        payment_guard.show_plans(conn, guard_identifier, redirect_after)
        |> Plug.Conn.halt()

      grant_for_guard ->
        grant_for_guard = payment_guard.use_grant(shop, grant_for_guard)
        Plug.Conn.put_private(conn, :grant_for_guard, grant_for_guard)
    end
  end
end
