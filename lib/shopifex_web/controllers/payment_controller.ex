defmodule ShopifexWeb.PaymentController do
  @moduledoc """
  You can use this module inside of another controller to handle initial iFrame load and shop installation

  Example:

  mix phx.gen.html Shops Plan plans name:string price:string features:array grants:array test:boolean
  mix phx.gen.html Shops Grant grants shop:references:shops charge_id:integer grants:array

  ```elixir
  defmodule MyAppWeb.PaymentController do
    use MyAppWeb, :controller
    use ShopifexWeb.PaymentController

    # Thats it! You can now configure your purchasable products :)
  end
  ```
  """
  defmacro __using__(_opts) do
    quote do
      require Logger

      @doc """
      Displays a list of available plans with which the user can access
      the guarded feature
      """
      def show_plans(conn, %{"guard" => guard}) do
        plans = Shopifex.Shops.list_plans_granting_guard(guard)

        conn
        |> put_view(ShopifexWeb.PaymentView)
        |> put_layout({ShopifexWeb.LayoutView, "app.html"})
        |> render("show-plans.html",
          plans: plans,
          guard: guard,
          shop_url: conn.private.shop_url
        )
      end

      def select_plan(conn, %{"plan_id" => plan_id}) do
        plan = Shopifex.Shops.get_plan!(plan_id)
        shop = conn.private.shop

        redirect_uri = Application.get_env(:shopifex, :payment_redirect_uri)

        body =
          Jason.encode!(%{
            recurring_application_charge: %{
              name: plan.name,
              price: plan.price,
              test: plan.test,
              return_url: "#{redirect_uri}?plan_id=#{plan_id}"
            }
          })

        case HTTPoison.post(
               "https://#{shop.url}/admin/api/2020-10/recurring_application_charges.json",
               body,
               "X-Shopify-Access-Token": shop.access_token,
               "Content-Type": "application/json"
             ) do
          {:ok, resp} ->
            send_resp(conn, 200, resp.body)
        end
      end

      def complete_payment(conn, %{"charge_id" => charge_id, "plan_id" => plan_id}) do
        plan = Shopifex.Shops.get_plan!(plan_id)
        shop = conn.private.shop

        {:ok, _grant} =
          Shopifex.Shops.create_grant(%{shop: shop, charge_id: charge_id, grants: plan.grants})

        api_key = Application.get_env(:shopifex, :api_key)

        # TODO: have this redirect to the page that the user was trying to access before they
        # got blocked by the paywall. Likely with Cachex or something.

        redirect(conn, external: "https://#{shop.url}/admin/apps/#{api_key}")
      end
    end
  end
end
