defmodule Shopifex.Plug.PaymentGuard do
  @moduledoc """
  Add payment guards to your routes or controllers!

  ## Examples:

  ```elixir
  defmodule MyAppWeb.AdminLinkController do
    use MyAppWeb, :controller
    require Logger

    plug Shopifex.Plug.PaymentGuard, "premium_plan" when action in [:premium_function]

    def premium_function(conn, _params) do
      # Wow, much premium.
      conn
      |> send_resp(200, "success")
    end
  end
  ```
  """
  require Logger

  @router_helpers Module.concat([
                    Application.compile_env(:shopifex, :web_module, ShopifexWeb),
                    Router,
                    Helpers
                  ])

  def init(options) do
    # initialize options
    options
  end

  @doc """
  This makes sure the shop in the session contains a payment which unlocks the guard.

  If no payment is present which unlocks the guard, the conn will be redirected to your
  application's PaymentController.show_plans route.
  """
  def call(conn, guard_identifier) do
    payment_guard = Application.fetch_env!(:shopifex, :payment_guard)

    shop = Shopifex.Plug.current_shop(conn)

    case payment_guard.grant_for_guard(shop, guard_identifier) do
      nil ->
        Logger.info("Payment guard blocked request")
        redirect_after = URI.encode_www_form("#{conn.request_path}?#{conn.query_string}")

        show_plans_url =
          @router_helpers.payment_path(conn, :show_plans, %{
            guard_identifier: guard_identifier,
            redirect_after: redirect_after,
            token: Shopifex.Plug.session_token(conn)
          })

        conn
        |> Phoenix.Controller.redirect(to: show_plans_url)
        |> Plug.Conn.halt()

      grant_for_guard ->
        grant_for_guard = payment_guard.use_grant(shop, grant_for_guard)
        Plug.Conn.put_private(conn, :grant_for_guard, grant_for_guard)
    end
  end
end
