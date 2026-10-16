defmodule ShopifexWeb.PaymentController do
  @moduledoc """
  Controller behaviour for Shopify billing, plan selection, and charge verification.

  Use this module inside your application's payment controller:

  ```elixir
  defmodule MyAppWeb.PaymentController do
    use MyAppWeb, :controller
    use ShopifexWeb.PaymentController
  end
  ```

  ### Billing Flow

  1. Merchant hits a pay-walled action guarded by `Shopifex.Plug.PaymentGuard`.
  2. If no valid grant exists, the merchant is redirected to `/payment/show-plans`.
  3. Selecting a plan sends a POST to `/payment/select-plan`, which creates a Shopify
     charge (`appSubscriptionCreate` or `appPurchaseOneTimeCreate`) and binds the charge
     cryptographically via `bind_charge/4`.
  4. The merchant approves the charge in Shopify and is redirected back to `/payment/complete`.
  5. `complete_payment/2` validates the signed charge binding, verifies that the charge is
     active in Shopify via `verify_charge/3`, creates the `Grant` record, and invokes
     `after_payment/5`.

  ### Custom Select-Plan Actions

  If your application defines a custom action to initiate charges (instead of the standard
  `select_plan/2`), you must call `ShopifexWeb.PaymentController.bind_charge/4` before
  redirecting the merchant to Shopify's confirmation URL.
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

  @doc """
  Creates a charge in Shopify for the given plan.
  """
  @callback create_charge(
              shop :: map(),
              plan :: map()
            ) :: {:ok, map()} | {:error, term()}

  @doc """
  Verifies that the charge has been approved and is active in Shopify before granting access.
  """
  @callback verify_charge(
              shop :: map(),
              plan :: map(),
              charge_id :: String.t() | integer()
            ) :: :ok | {:error, term()}

  @optional_callbacks render_plans: 3,
                      after_payment: 5,
                      test_charge?: 2,
                      create_charge: 2,
                      verify_charge: 3

  @doc """
  Cryptographically binds a pending charge to `{shop, plan, redirect_after}` and
  stores it under `charge_id` in the configured `:redirect_after_agent`.

  Custom `select_plan` actions must call this function before redirecting the
  merchant to Shopify's confirmation URL.
  """
  @spec bind_charge(
          shop :: map(),
          plan :: map(),
          charge_id :: String.t() | integer(),
          redirect_after :: String.t()
        ) :: :ok
  def bind_charge(shop, plan, charge_id, redirect_after) do
    redirect_after_agent =
      Application.get_env(:shopifex, :redirect_after_agent, Shopifex.RedirectAfterAgent)

    signed_binding =
      Shopifex.ChargeBinding.sign(%{
        shop_url: Shopifex.Shops.get_url(shop),
        plan_id: to_string(plan.id),
        redirect_after: redirect_after
      })

    redirect_after_agent.set(charge_id, signed_binding)
  end

  @doc false
  # `create_charge/2` (via `Shopifex.API.graphql/3`) can fail with a GraphQL
  # `userErrors` list/map, a `{status, body}` tuple, a `%Req.TransportError{}`,
  # or a `{:token_refresh_failed, reason}` tuple. Only the first is
  # JSON-encodable as-is; everything else must be normalised before
  # `Jason.encode!/1` or the 422 response itself would crash with a 500.
  @spec normalize_charge_errors(term()) :: list() | map()
  def normalize_charge_errors(errors) when is_list(errors), do: errors
  def normalize_charge_errors(%_{} = reason), do: [%{"message" => inspect(reason)}]
  def normalize_charge_errors(errors) when is_map(errors), do: errors
  def normalize_charge_errors(reason), do: [%{"message" => inspect(reason)}]

  defmacro __using__(_opts) do
    quote do
      @behaviour ShopifexWeb.PaymentController

      require Logger

      def show_plans(conn, params) do
        path_prefix = Application.get_env(:shopifex, :path_prefix, "")
        # Embedded apps re-authenticate via Shopify's per-load id_token, so the
        # post-payment redirect just returns to the app root.
        default_redirect_after = path_prefix <> "/"

        render_plans(
          conn,
          Map.get(params, "guard_identifier"),
          Map.get(params, "redirect_after", default_redirect_after)
        )
      end

      def select_plan(conn, %{"plan_id" => plan_id, "redirect_after" => redirect_after}) do
        payment_guard = Application.fetch_env!(:shopifex, :payment_guard)
        plan = payment_guard.get_plan(plan_id)
        shop = Shopifex.Plug.current_shop(conn)

        case create_charge(shop, plan) do
          {:ok, charge} ->
            ShopifexWeb.PaymentController.bind_charge(shop, plan, charge["id"], redirect_after)
            send_resp(conn, 200, Jason.encode!(charge))

          {:error, errors} ->
            conn
            |> put_status(422)
            |> put_resp_header("content-type", "application/json")
            |> send_resp(
              422,
              Jason.encode!(%{
                "errors" => ShopifexWeb.PaymentController.normalize_charge_errors(errors)
              })
            )
        end
      end

      @impl ShopifexWeb.PaymentController
      def test_charge?(_shop, %{test: test?} = _plan), do: test?

      @doc """
      Creates a Shopify charge for the given plan and returns
      `{:ok, %{"id" => charge_id, "confirmation_url" => url}}`.

      Recurring plans (`type: "recurring_application_charge"`) use
      `appSubscriptionCreate` (monthly by default, annual when `plan.annual` is
      true). One-time plans (`type: "application_charge"`) use
      `appPurchaseOneTimeCreate`. Both run through `Shopifex.API.graphql/3`
      (which keeps the access token fresh and uses the configured API version)
      and match Shopify's documented GraphQL shape — line items are passed as a
      `$lineItems` variable rather than interpolated into the query, and no
      `@idempotent` directive is sent (Shopify does not document one for these
      mutations).

      ### Optional recurring features

      The default builds a single recurring line item from `plan.price` /
      `plan.annual`. Supply extra plan data to opt into Shopify features:

        * `:replacement_behavior` — an `AppSubscriptionReplacementBehavior`
          (e.g. `:apply_immediately`, `"STANDARD"`).
        * `:currency_code` — defaults to `"USD"`.
        * `:discount` — an `AppSubscriptionDiscountInput` map merged into the
          default line item's pricing details.
        * `:line_items` — a fully-formed list of `AppSubscriptionLineItemInput`
          maps. When given, it overrides the default line item entirely, so you
          can pass multiple line items, usage (`appUsagePricingDetails`) pricing,
          or custom discounts.

      Overridable — define your own `create_charge/2` to customise pricing.
      """
      @impl ShopifexWeb.PaymentController
      def create_charge(shop, %{type: "recurring_application_charge"} = plan) do
        mutation = """
        mutation appSubscriptionCreate($name: String!, $returnUrl: URL!, $test: Boolean!, $trialDays: Int!, $lineItems: [AppSubscriptionLineItemInput!]!, $replacementBehavior: AppSubscriptionReplacementBehavior) {
          appSubscriptionCreate(name: $name, returnUrl: $returnUrl, test: $test, trialDays: $trialDays, lineItems: $lineItems, replacementBehavior: $replacementBehavior) {
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
        """

        variables = %{
          name: plan.name,
          test: test_charge?(shop, plan),
          trialDays: Map.get(plan, :trial_days, 0),
          returnUrl: charge_return_url(shop, plan),
          lineItems: subscription_line_items(plan),
          replacementBehavior:
            normalize_replacement_behavior(Map.get(plan, :replacement_behavior))
        }

        shop
        |> Shopifex.API.graphql(mutation, variables)
        |> unwrap_charge("appSubscriptionCreate", "appSubscription")
      end

      def create_charge(shop, %{type: "application_charge"} = plan) do
        mutation = """
        mutation appPurchaseOneTimeCreate($name: String!, $returnUrl: URL!, $test: Boolean!, $price: MoneyInput!) {
          appPurchaseOneTimeCreate(name: $name, returnUrl: $returnUrl, test: $test, price: $price) {
            appPurchaseOneTime {
              id
            }
            confirmationUrl
            userErrors {
              field
              message
            }
          }
        }
        """

        variables = %{
          name: plan.name,
          price: %{amount: to_string(plan.price), currencyCode: charge_currency_code(plan)},
          test: test_charge?(shop, plan),
          returnUrl: charge_return_url(shop, plan)
        }

        shop
        |> Shopifex.API.graphql(mutation, variables)
        |> unwrap_charge("appPurchaseOneTimeCreate", "appPurchaseOneTime")
      end

      # A caller-supplied `:line_items` list wins outright (multiple line items,
      # usage pricing, custom discounts). Otherwise build the single recurring
      # line item from price/interval, optionally with a discount.
      defp subscription_line_items(%{line_items: line_items}) when is_list(line_items),
        do: line_items

      defp subscription_line_items(plan) do
        interval = if Map.get(plan, :annual, false), do: "ANNUAL", else: "EVERY_30_DAYS"

        pricing =
          %{
            price: %{amount: to_string(plan.price), currencyCode: charge_currency_code(plan)},
            interval: interval
          }
          |> maybe_put(:discount, Map.get(plan, :discount))

        [%{plan: %{appRecurringPricingDetails: pricing}}]
      end

      defp charge_currency_code(plan), do: Map.get(plan, :currency_code, "USD")

      defp normalize_replacement_behavior(nil), do: nil

      defp normalize_replacement_behavior(value) when is_atom(value),
        do: value |> Atom.to_string() |> String.upcase()

      defp normalize_replacement_behavior(value) when is_binary(value), do: String.upcase(value)

      defp maybe_put(map, _key, nil), do: map
      defp maybe_put(map, key, value), do: Map.put(map, key, value)

      defp charge_return_url(shop, plan) do
        redirect_uri = Application.get_env(:shopifex, :payment_redirect_uri)
        "#{redirect_uri}?plan_id=#{plan.id}&shop=#{Shopifex.Shops.get_url(shop)}"
      end

      defp unwrap_charge(result, mutation_field, charge_field) do
        case result do
          {:ok,
           %{
             ^mutation_field => %{
               "userErrors" => [],
               ^charge_field => %{"id" => gid},
               "confirmationUrl" => confirmation_url
             }
           }} ->
            {:ok,
             %{"id" => List.last(String.split(gid, "/")), "confirmation_url" => confirmation_url}}

          {:ok, %{^mutation_field => %{"userErrors" => errors}}} ->
            {:error, errors}

          error ->
            error
        end
      end

      @impl ShopifexWeb.PaymentController
      def verify_charge(shop, %{type: "recurring_application_charge"}, charge_id) do
        query = """
        query appSubscriptionStatus($id: ID!) {
          node(id: $id) {
            ... on AppSubscription {
              status
            }
          }
        }
        """

        variables = %{id: "gid://shopify/AppSubscription/#{charge_id}"}

        case Shopifex.API.graphql(shop, query, variables) do
          {:ok, %{"node" => %{"status" => status}}} when status in ["ACTIVE", "ACCEPTED"] ->
            :ok

          {:ok, %{"node" => %{"status" => status}}} ->
            {:error, {:unexpected_status, status}}

          {:ok, %{"node" => nil}} ->
            {:error, :not_found}

          {:error, reason} ->
            {:error, reason}

          other ->
            {:error, other}
        end
      end

      def verify_charge(shop, %{type: "application_charge"}, charge_id) do
        query = """
        query appPurchaseOneTimeStatus($id: ID!) {
          node(id: $id) {
            ... on AppPurchaseOneTime {
              status
            }
          }
        }
        """

        variables = %{id: "gid://shopify/AppPurchaseOneTime/#{charge_id}"}

        case Shopifex.API.graphql(shop, query, variables) do
          {:ok, %{"node" => %{"status" => "ACTIVE"}}} ->
            :ok

          {:ok, %{"node" => %{"status" => status}}} ->
            {:error, {:unexpected_status, status}}

          {:ok, %{"node" => nil}} ->
            {:error, :not_found}

          {:error, reason} ->
            {:error, reason}

          other ->
            {:error, other}
        end
      end

      def verify_charge(_shop, plan, _charge_id) do
        {:error, {:unknown_plan_type, Map.get(plan, :type)}}
      end

      # Only string params reach the binding lookup below: the return URL Shopify
      # redirects to (`charge_return_url/2`) always carries strings, and a
      # bracket-syntax `plan_id[x]=y` (a map) would otherwise raise *after* the
      # binding was popped, bypassing the restore in `complete_bound_payment/5`.
      def complete_payment(conn, %{
            "charge_id" => raw_charge_id,
            "plan_id" => raw_plan_id,
            "shop" => shop_url
          })
          when is_binary(raw_charge_id) and is_binary(raw_plan_id) and is_binary(shop_url) do
        case Integer.parse(raw_charge_id) do
          {charge_id, ""} ->
            complete_bound_payment(conn, charge_id, raw_charge_id, raw_plan_id, shop_url)

          _ ->
            Logger.error(
              "[shopifex] complete_payment: invalid non-integer charge_id #{inspect(raw_charge_id)}"
            )

            payment_forbidden(conn)
        end
      end

      def complete_payment(conn, _params), do: payment_forbidden(conn)

      # The store's `get/1` consumes the binding. From the moment it is popped,
      # every failure below puts it back — the blob is signed, so restoring what
      # was read is safe — so a scanner probing sequential charge ids with a
      # wrong shop/plan cannot deny the legitimate merchant's confirmation.
      defp complete_bound_payment(conn, charge_id, raw_charge_id, raw_plan_id, shop_url) do
        store = Application.get_env(:shopifex, :redirect_after_agent, Shopifex.RedirectAfterAgent)

        case store.get(charge_id) do
          nil ->
            Logger.error(
              "[shopifex] complete_payment: no redirect-after entry for charge_id=" <>
                "#{inspect(raw_charge_id)} (shop=#{inspect(shop_url)}). Treating as forbidden. " <>
                "If the merchant was actually charged, the grant was just dropped: the default " <>
                "RedirectAfterAgent is in-memory and node-local, so the confirmation redirect " <>
                "missed on a multi-node deploy. Configure a persistent " <>
                "config :shopifex, :redirect_after_agent (e.g. Shopifex.RedirectAfter.Ecto)."
            )

            payment_forbidden(conn)

          binding_blob ->
            # A raise past this point (a plan deleted while the charge was
            # pending, a custom `get_plan/1` returning nil, a store outage)
            # must not consume the binding either: put it back, then re-raise.
            result =
              try do
                verify_binding_and_grant(conn, binding_blob, charge_id, raw_plan_id, shop_url)
              rescue
                exception ->
                  store.set(charge_id, binding_blob)
                  reraise exception, __STACKTRACE__
              end

            case result do
              {:ok, conn} ->
                conn

              {:error, reason} ->
                store.set(charge_id, binding_blob)
                payment_failure(conn, reason, charge_id)
            end
        end
      end

      defp verify_binding_and_grant(conn, binding_blob, charge_id, raw_plan_id, shop_url) do
        payment_guard = Application.fetch_env!(:shopifex, :payment_guard)

        with {:ok, bound} <-
               payment_tag(Shopifex.ChargeBinding.verify(binding_blob), :invalid_binding),
             :ok <- payment_binding_matches(bound, shop_url, raw_plan_id),
             {:ok, shop} <- payment_shop(shop_url),
             plan = payment_guard.get_plan(raw_plan_id),
             :ok <-
               payment_tag(verify_charge(shop, plan, to_string(charge_id)), :charge_not_active),
             {:ok, grant} <-
               payment_tag(payment_guard.create_grant(shop, plan, charge_id), :grant_failed) do
          {:ok, after_payment(conn, shop, plan, grant, URI.decode_www_form(bound.redirect_after))}
        end
      end

      defp payment_tag({:ok, _} = ok, _tag), do: ok
      defp payment_tag(:ok, _tag), do: :ok
      defp payment_tag({:error, reason}, tag), do: {:error, {tag, reason}}
      defp payment_tag(other, tag), do: {:error, {tag, other}}

      defp payment_binding_matches(
             %{shop_url: bound_shop, plan_id: bound_plan},
             shop_url,
             raw_plan_id
           ) do
        if bound_shop == shop_url and bound_plan == to_string(raw_plan_id) do
          :ok
        else
          {:error, {:binding_mismatch, bound_shop, bound_plan, shop_url, raw_plan_id}}
        end
      end

      defp payment_shop(shop_url) do
        case Shopifex.Shops.get_shop_by_url(shop_url) do
          nil -> {:error, :shop_not_found}
          shop -> {:ok, shop}
        end
      end

      defp payment_failure(conn, {:invalid_binding, reason}, _charge_id) do
        Logger.error(
          "[shopifex] complete_payment: invalid charge binding (#{inspect(reason)}). If using a custom select_plan action, ensure it calls ShopifexWeb.PaymentController.bind_charge/4."
        )

        payment_forbidden(conn)
      end

      defp payment_failure(
             conn,
             {:binding_mismatch, bound_shop, bound_plan, shop_url, raw_plan_id},
             _
           ) do
        Logger.error(
          "[shopifex] complete_payment: charge binding mismatch: expected shop #{inspect(bound_shop)} and plan #{inspect(bound_plan)}, got shop #{inspect(shop_url)} and plan #{inspect(raw_plan_id)}"
        )

        payment_forbidden(conn)
      end

      defp payment_failure(conn, :shop_not_found, _charge_id), do: payment_forbidden(conn)

      defp payment_failure(conn, {:charge_not_active, reason}, charge_id) do
        Logger.info(
          "[shopifex] complete_payment: charge not active for charge_id=#{charge_id}: #{inspect(reason)}"
        )

        send_resp(conn, 403, "charge not active")
      end

      # The merchant has paid but the grant could not be written: fail loudly
      # (the binding was restored, so a retry can succeed once the cause is fixed).
      defp payment_failure(_conn, {:grant_failed, %Ecto.Changeset{} = changeset}, _charge_id) do
        Logger.error(
          "[shopifex] complete_payment: grant changeset rejected attributes: #{inspect(changeset.errors)}"
        )

        raise "Grant changeset rejected attributes: #{inspect(changeset.errors)}"
      end

      defp payment_failure(_conn, {:grant_failed, reason}, _charge_id) do
        Logger.error("[shopifex] complete_payment: create_grant failed: #{inspect(reason)}")
        raise "create_grant failed: #{inspect(reason)}"
      end

      defp payment_forbidden(conn),
        do: send_resp(conn, 403, "Could not verify this payment confirmation.")

      @impl ShopifexWeb.PaymentController
      def render_plans(conn, guard_identifier, redirect_after) do
        conn
        |> put_view(ShopifexWeb.PaymentHTML)
        |> put_root_layout(html: false)
        |> put_layout(html: {ShopifexWeb.Layouts, :app})
        |> render("show_plans.html",
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

      defoverridable render_plans: 3,
                     after_payment: 5,
                     test_charge?: 2,
                     create_charge: 2,
                     verify_charge: 3
    end
  end
end
