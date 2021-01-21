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

  @doc """
  An optional callback called after a payment is completed. By default, this function
  redirects the user to the app index within their Shopify admin panel.

  ## Example

      def after_payment(conn, shop, plan, grant) do
        # send yourself an e-mail about payment

        # follow default behaviour.
        super(conn, shop, plan, grant)
      end
  """
  @callback after_payment(
              Plug.Conn.t(),
              Ecto.Schema.t(),
              Ecto.Schema.t(),
              Ecto.Schema.t()
            ) ::
              Plug.Conn.t()
  @optional_callbacks after_payment: 4

  defmacro __using__(_opts) do
    quote do
      @behaviour ShopifexWeb.PaymentController

      require Logger

      @doc """
      Displays a list of available plans with which the user can access
      the guarded feature
      """
      def show_plans(conn, %{"guard" => guard, "redirect_after" => redirect_after}) do
        plans = Shopifex.Shops.list_plans_granting_guard(guard)

        conn
        |> put_view(ShopifexWeb.PaymentView)
        |> put_layout({ShopifexWeb.LayoutView, "app.html"})
        |> render("show-plans.html",
          plans: plans,
          guard: guard,
          redirect_after: redirect_after,
          shop_url: conn.private.shop_url
        )
      end

      def select_plan(conn, %{"plan_id" => plan_id, "redirect_after" => redirect_after}) do
        plan = Shopifex.Shops.get_plan!(plan_id)
        shop = conn.private.shop

        {:ok, charge} = create_charge(shop, plan)

        Shopifex.RedirectAfterAgent.set(charge["id"], redirect_after)

        send_resp(conn, 200, Jason.encode!(charge))
      end

      defp create_charge(shop, plan = %{type: "recurring_application_charge"}) do
        redirect_uri = Application.get_env(:shopifex, :payment_redirect_uri)

        body =
          Jason.encode!(%{
            recurring_application_charge: %{
              name: plan.name,
              price: plan.price,
              test: plan.test,
              return_url: "#{redirect_uri}?plan_id=#{plan.id}"
            }
          })

        case HTTPoison.post(
               "https://#{shop.url}/admin/api/2021-01/recurring_application_charges.json",
               body,
               "X-Shopify-Access-Token": shop.access_token,
               "Content-Type": "application/json"
             ) do
          {:ok, resp} ->
            {:ok, Jason.decode!(resp.body)["recurring_application_charge"]}
        end
      end

      defp create_charge(shop, plan = %{type: "application_charge"}) do
        redirect_uri = Application.get_env(:shopifex, :payment_redirect_uri)

        body =
          Jason.encode!(%{
            application_charge: %{
              name: plan.name,
              price: plan.price,
              test: plan.test,
              return_url: "#{redirect_uri}?plan_id=#{plan.id}"
            }
          })

        case HTTPoison.post(
               "https://#{shop.url}/admin/api/2021-01/application_charges.json",
               body,
               "X-Shopify-Access-Token": shop.access_token,
               "Content-Type": "application/json"
             ) do
          {:ok, resp} ->
            {:ok, Jason.decode!(resp.body)["application_charge"]}
        end
      end

      def complete_payment(conn, %{
            "charge_id" => charge_id,
            "plan_id" => plan_id
          }) do
        plan = Shopifex.Shops.get_plan!(plan_id)
        shop = conn.private.shop

        {:ok, grant} =
          Shopifex.Shops.create_grant(%{
            shop: shop,
            charge_id: charge_id,
            grants: plan.grants,
            remaining_usages: plan.usages
          })

        after_payment(conn, shop, plan, grant)
      end

      @impl ShopifexWeb.PaymentController
      def after_payment(conn, shop, plan, grant) do
        redirect_after = Shopifex.RedirectAfterAgent.get(grant.charge_id)

        api_key = Application.get_env(:shopifex, :api_key)
        redirect(conn, external: "https://#{shop.url}/admin/apps/#{api_key}#{redirect_after}")
      end

      defoverridable after_payment: 4
    end
  end
end
