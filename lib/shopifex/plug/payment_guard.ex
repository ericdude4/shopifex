defmodule Shopifex.Plug.PaymentGuard do
  import Plug.Conn
  import Phoenix.Controller
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

    case payment_guard.grant_for_guard(conn.private.shop, guard_identifier) do
      nil ->
        Logger.info("Payment guard blocked request")
        redirect_after = URI.encode_www_form("#{conn.request_path}?#{conn.query_string}")

        conn
        |> put_view(ShopifexWeb.PaymentView)
        |> put_layout({ShopifexWeb.LayoutView, "app.html"})
        |> render("show-plans.html",
          guard: guard_identifier,
          redirect_after: redirect_after
        )
        |> halt()

      grant_for_guard ->
        grant_for_guard = payment_guard.use_grant(conn.private.shop, grant_for_guard)
        Plug.Conn.put_private(conn, :grant_for_guard, grant_for_guard)
    end
  end
end
