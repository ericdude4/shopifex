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
  Display the available payment plans for the user to select.
  """
  @callback render_plans(
              conn :: Plug.Conn.t(),
              guard_identifier :: String.t(),
              redirect_after :: String.t()
            ) :: Plug.Conn.t()

  @doc """
  An optional callback called after a payment is completed. By default, this function
  redirects the user to the app index within their Shopify admin panel.

  ## Example

      def after_payment(conn, shop, plan, grant, redirect_after) do
        # send yourself an e-mail about payment

        # follow default behaviour.
        super(conn, shop, plan, grant, redirect_after)
      end
  """
  @callback after_payment(
              Plug.Conn.t(),
              Ecto.Schema.t(),
              Ecto.Schema.t(),
              Ecto.Schema.t(),
              String.t()
            ) ::
              Plug.Conn.t()

  @doc """
  Given a shop and plan, return boolean for whether the charge should be created as
  a test charge.
  """
  @callback test_charge?(shop :: Ecto.Schema.t(), plan :: map()) :: boolean()

  @optional_callbacks render_plans: 3, after_payment: 5, test_charge?: 2

  defmacro __using__(_opts) do
    quote do
      @behaviour ShopifexWeb.PaymentController

      require Logger

      def show_plans(conn, params) do
        payment_guard = Application.fetch_env!(:shopifex, :payment_guard)
        path_prefix = Application.get_env(:shopifex, :path_prefix, "")
        default_redirect_after = path_prefix <> "/?token=" <> Guardian.Plug.current_token(conn)

        render_plans(
          conn,
          Map.get(params, "guard_identifier"),
          Map.get(params, "redirect_after", default_redirect_after)
        )
      end

      def select_plan(conn, %{"plan_id" => plan_id, "redirect_after" => redirect_after}) do
        payment_guard = Application.fetch_env!(:shopifex, :payment_guard)

        redirect_after_agent =
          Application.get_env(:shopifex, :redirect_after_agent, Shopifex.RedirectAfterAgent)

        plan = payment_guard.get_plan(plan_id)

        shop =
          case conn.private do
            %{shop: shop} -> shop
            %{guardian_default_resource: shop} -> shop
          end

        {:ok, charge} = create_charge(shop, plan)

        redirect_after_agent.set(charge["id"], redirect_after)

        send_resp(conn, 200, Jason.encode!(charge))
      end

      @impl ShopifexWeb.PaymentController
      def test_charge?(_shop, %{test: test?} = _plan), do: test?

      # annual billing is only possible w/ the GraphQL API
      defp create_charge(shop, plan = %{type: "recurring_application_charge", annual: true}) do
        redirect_uri = Application.get_env(:shopifex, :payment_redirect_uri)

        case Neuron.query(
               """
               mutation appSubscriptionCreate($name: String!, $return_url: URL!, $test: Boolean!, $price: Decimal!) {
                 appSubscriptionCreate(name: $name, returnUrl: $return_url, test: $test, trialDays: $trial_days, lineItems: [{plan: {appRecurringPricingDetails: {price: {amount: $price, currencyCode: USD}, interval: ANNUAL}}}]) {
                   appSubscription {
                     id
                   }
                   confirmationUrl
                   userErrors {
                     field
                     message
                   }
                 }
               }
               """,
               %{
                 name: plan.name,
                 price: plan.price,
                 test: test_charge?(shop, plan),
                 trial_days: Map.get(plan, :trial_days, 0),
                 return_url:
                   "#{redirect_uri}?plan_id=#{plan.id}&shop=#{Shopifex.Shops.get_url(shop)}"
               },
               url: "https://#{Shopifex.Shops.get_url(shop)}/admin/api/2023-04/graphql.json",
               headers: [
                 "X-Shopify-Access-Token": shop.access_token,
                 "Content-Type": "application/json"
               ]
             ) do
          {:ok, %Neuron.Response{body: body}} ->
            app_subscription_create = body["data"]["appSubscriptionCreate"]

            # id comes back in this format: "gid://shopify/AppSubscription/4019552312"
            <<_::binary-size(30)>> <> id = app_subscription_create["appSubscription"]["id"]
            confirmation_url = app_subscription_create["confirmationUrl"]

            {:ok, %{"id" => id, "confirmation_url" => confirmation_url}}
        end
      end

      defp create_charge(shop, plan = %{type: "recurring_application_charge"}) do
        redirect_uri = Application.get_env(:shopifex, :payment_redirect_uri)

        body =
          Jason.encode!(%{
            recurring_application_charge: %{
              name: plan.name,
              price: plan.price,
              test: test_charge?(shop, plan),
              trial_days: Map.get(plan, :trial_days, 0),
              return_url:
                "#{redirect_uri}?plan_id=#{plan.id}&shop=#{Shopifex.Shops.get_url(shop)}"
            }
          })

        case HTTPoison.post(
               "https://#{Shopifex.Shops.get_url(shop)}/admin/api/2023-04/recurring_application_charges.json",
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
              test: test_charge?(shop, plan),
              return_url:
                "#{redirect_uri}?plan_id=#{plan.id}&shop=#{Shopifex.Shops.get_url(shop)}"
            }
          })

        case HTTPoison.post(
               "https://#{Shopifex.Shops.get_url(shop)}/admin/api/2023-04/application_charges.json",
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
            "plan_id" => plan_id,
            "shop" => shop_url
          }) do
        redirect_after_agent =
          Application.get_env(:shopifex, :redirect_after_agent, Shopifex.RedirectAfterAgent)

        # Shopify's API doesn't provide an HMAC validation on
        # this return-url. Use the token param in the redirect_after
        # url that is associated with this charge_id to validate
        # the request and get the current shop
        with redirect_after when redirect_after != nil <-
               redirect_after_agent.get(charge_id),
             redirect_after <- URI.decode_www_form(redirect_after),
             shop when not is_nil(shop) <- Shopifex.Shops.get_shop_by_url(shop_url) do
          payment_guard = Application.fetch_env!(:shopifex, :payment_guard)

          plan = payment_guard.get_plan(plan_id)

          {:ok, grant} = payment_guard.create_grant(shop, plan, charge_id)

          after_payment(conn, shop, plan, grant, redirect_after)
        else
          _ ->
            {:error, :forbidden}
        end
      end

      @impl ShopifexWeb.PaymentController
      def render_plans(conn, guard_identifier, redirect_after) do
        conn
        |> put_view(ShopifexWeb.PaymentView)
        |> put_layout({ShopifexWeb.LayoutView, "app.html"})
        |> render("show-plans.html",
          guard: guard_identifier,
          redirect_after: redirect_after
        )
      end

      @impl ShopifexWeb.PaymentController
      def after_payment(conn, shop, _plan, _grant, redirect_after) do
        api_key = Application.get_env(:shopifex, :api_key)

        redirect(conn,
          external:
            "https://#{Shopifex.Shops.get_url(shop)}/admin/apps/#{api_key}#{redirect_after}"
        )
      end

      defoverridable render_plans: 3, after_payment: 5, test_charge?: 2
    end
  end
end
