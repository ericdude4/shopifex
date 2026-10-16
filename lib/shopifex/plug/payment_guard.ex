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

  def init(options) do
    # initialize options
    options
  end

  @doc """
  This makes sure the shop in the session contains a payment which unlocks the guard.

  If no payment is present which unlocks the guard (or remaining usages are exhausted),
  the conn will be redirected to your application's PaymentController.show_plans route.
  """
  def call(conn, guard_identifier) do
    payment_guard = Application.fetch_env!(:shopifex, :payment_guard)
    shop = Shopifex.Plug.current_shop(conn)

    with grant when not is_nil(grant) <- payment_guard.grant_for_guard(shop, guard_identifier),
         updated_grant when not is_nil(updated_grant) <- payment_guard.use_grant(shop, grant) do
      Plug.Conn.put_private(conn, :grant_for_guard, updated_grant)
    else
      _ ->
        Logger.info("Payment guard blocked request")
        redirect_after = URI.encode_www_form("#{conn.request_path}?#{conn.query_string}")

        prefix = Application.get_env(:shopifex, :path_prefix, "")
        show_plans_path = "#{prefix}/payment/show-plans"

        # A request authenticated without an App Bridge `id_token` (legacy HMAC
        # / non-embedded) has nothing to forward, so the redirect carries a
        # short-lived token bound to the plans path — accepted by ShopifySession
        # there and nowhere else, so a captured link cannot be replayed on other
        # routes or used to mint a fresh credential. An `id_token`, when present,
        # is forwarded as `token` and tried first.
        params =
          %{
            "guard_identifier" => guard_identifier,
            "redirect_after" => redirect_after
          }
          |> maybe_put("token", Shopifex.Plug.session_token(conn))
          |> maybe_put("redirect_token", redirect_token(shop, show_plans_path))

        conn
        |> Phoenix.Controller.redirect(to: "#{show_plans_path}?#{URI.encode_query(params)}")
        |> Plug.Conn.halt()
    end
  end

  defp maybe_put(params, _key, nil), do: params
  defp maybe_put(params, key, value), do: Map.put(params, key, value)

  defp redirect_token(nil, _path), do: nil

  defp redirect_token(shop, path),
    do: Shopifex.Plug.sign_redirect(Shopifex.Shops.get_url(shop), path)
end
