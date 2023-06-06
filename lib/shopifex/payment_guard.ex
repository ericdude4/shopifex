defmodule Shopifex.PaymentGuard do
  @moduledoc """
  Context behaviour responsible for fetching and using payment grants.
  """

  @type plan :: %{
          id: String.t() | pos_integer(),
          name: String.t(),
          price: String.t(),
          type: String.t(),
          test: boolean()
        }

  @type grant :: %{
          charge_id: pos_integer(),
          grants: [String.t()],
          remaining_usages: pos_integer(),
          total_usages: pos_integer()
        }

  @type shop :: %{access_token: String.t(), scope: String.t(), url: String.t()}

  @type guard :: String.t()

  @doc """
  Returns a payment record which grants access to the payment guard.
  Default behaviour filters where `remaining_usages` is greater than
  0 or has a nil value (unlimited usage). You can also provide a list of
  grants in place of the first parameter in order to avoid a trip to the
  database.
  """
  @callback grant_for_guard(shop() | [grant()], guard()) :: grant() | boolean()

  @doc """
  Returns a list of valid grants which are associated with the store.
  """
  @callback grants_for_shop(shop()) :: [grant()]

  @doc """
  Updates the grant to reflect the usage of it in some way. Defaults to decrementing
  the `remaining_usages` property if it's not nil. If it is nil, the grant has
  unlimited usages
  """
  @callback use_grant(shop(), grant()) :: grant()

  @doc """
  After payment has been accepted, this function is meant to persist the
  payment. Default behaviour is to create a grant schema record. `charge_id` is
  the external id for the Shopify charge record.
  """
  @callback create_grant(shop :: shop(), plan :: plan(), charge_id :: pos_integer()) ::
              {:ok, any()}

  @doc """
  Gets a plan with a given identifier
  """
  @callback get_plan(plan_id :: String.t() | pos_integer()) :: plan()

  @doc """
  Get a list of plans for shop based on provided guard
  """
  @callback list_available_plans_for_guard(shop :: shop(), guard :: guard()) :: [plan()]

  @optional_callbacks grant_for_guard: 2,
                      use_grant: 2,
                      get_plan: 1,
                      create_grant: 3,
                      list_available_plans_for_guard: 2

  defmacro __using__(_opts) do
    quote do
      @behaviour Shopifex.PaymentGuard

      import Plug.Conn, only: [halt: 1]
      import Phoenix.Controller, only: [put_view: 2, put_layout: 2, render: 3]
      import Ecto.Query, warn: false
      alias Ecto.Changeset

      def grant_schema, do: Application.fetch_env!(:shopifex, :grant_schema)
      def repo, do: Application.fetch_env!(:shopifex, :repo)

      @impl Shopifex.PaymentGuard
      def grant_for_guard(shop, guard) when is_struct(shop) do
        from(s in grant_schema(),
          where: s.shop_id == ^shop.id,
          where: ^guard in s.grants,
          where: is_nil(s.remaining_usages),
          or_where: s.remaining_usages > 0,
          limit: 1
        )
        |> repo().one()
      end

      def grant_for_guard(grants, guard) when is_list(grants) do
        # In this case, the list of grants is being provided as input, so just search that
        # set for a valid grant.
        Enum.find(grants, fn grant ->
          guard in grant.grants and
            (is_nil(grant.remaining_usages) or grant.remaining_usages > 0)
        end)
      end

      @impl Shopifex.PaymentGuard
      def grants_for_shop(shop) do
        from(s in grant_schema(),
          where: s.shop_id == ^shop.id,
          where: is_nil(s.remaining_usages),
          or_where: s.remaining_usages > 0
        )
        |> repo().all()
      end

      @impl Shopifex.PaymentGuard
      def get_plan(plan_id) do
        Shopifex.Shops.get_plan!(plan_id)
      end

      @impl Shopifex.PaymentGuard
      def list_available_plans_for_guard(shop, guard) do
        Shopifex.Shops.list_plans_granting_guard(guard)
      end

      @impl Shopifex.PaymentGuard
      def use_grant(_shop, grant) do
        grant
        |> Changeset.change()
        |> update_total_usages()
        |> update_remaining_usages()
        |> repo().update!()
      end

      defp update_total_usages(%Changeset{data: %{total_usages: total_usages}} = grant) do
        total_usages = if is_nil(total_usages), do: 0, else: total_usages

        grant
        |> Changeset.change(%{total_usages: total_usages + 1})
      end

      defp update_remaining_usages(%Changeset{data: %{remaining_usages: nil}} = grant_changeset),
        do: grant_changeset

      defp update_remaining_usages(
             %Changeset{data: %{remaining_usages: remaining_usages}} = grant_changeset
           ),
           do: Changeset.change(grant_changeset, %{remaining_usages: remaining_usages - 1})

      @impl Shopifex.PaymentGuard
      def create_grant(shop, plan, charge_id) do
        Shopifex.Shops.create_grant(%{
          shop_id: shop.id,
          charge_id: charge_id,
          grants: plan.grants,
          remaining_usages: plan.usages,
          total_usages: 0
        })
      end

      defoverridable grant_for_guard: 2,
                     grants_for_shop: 1,
                     use_grant: 2,
                     get_plan: 1,
                     create_grant: 3,
                     list_available_plans_for_guard: 2
    end
  end
end
