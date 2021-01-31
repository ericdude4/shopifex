defmodule Shopifex.PaymentGuard do
  @moduledoc """
  Context behaviour responsible for fetching and using payment grants.
  """

  @doc """
  Returns a payment record which grants access to the payment guard. Filters
  where `remaining_usages` is greater than 0 or has a nil value (unlimited usage).
  """
  @callback grant_for_guard(Ecto.Schema.t(), Ecto.Schema.t()) :: Ecto.Schema.t()
  @doc """
  Updates the grant to reflect the usage of it in some way. Defaults to decrementing
  the `remaining_usages` property if it's not nil. If it is nil, the grant has
  unlimited usages
  """
  @callback use_grant(Ecto.Schema.t(), Ecto.Schema.t()) :: Ecto.Schema.t()
  @optional_callbacks grant_for_guard: 2, use_grant: 2
  defmacro __using__(_opts) do
    quote do
      @behaviour Shopifex.PaymentGuard

      import Ecto.Query, warn: false
      alias Ecto.Changeset

      def grant_schema, do: Application.fetch_env!(:shopifex, :grant_schema)
      def repo, do: Application.fetch_env!(:shopifex, :repo)

      @impl Shopifex.PaymentGuard
      def grant_for_guard(shop, guard) do
        from(s in grant_schema(),
          where: s.shop_id == ^shop.id,
          where: ^guard in s.grants,
          where: is_nil(s.remaining_usages),
          or_where: s.remaining_usages > 0
        )
        |> repo().one()
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

      defoverridable grant_for_guard: 2, use_grant: 2
    end
  end
end
