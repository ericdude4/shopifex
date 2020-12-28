defmodule Shopifex.PaymentGuard do
  defmacro __using__(_opts) do
    quote do
      import Ecto.Query, warn: false

      def grant_schema, do: Application.fetch_env!(:shopifex, :grant_schema)
      def repo, do: Application.fetch_env!(:shopifex, :repo)

      @doc """
      Returns a payment record which grants access to the payment guard or nil
      """
      def grant_for_guard(shop, guard) do
        from(s in grant_schema(),
          where: s.shop_id == ^shop.id,
          where: ^guard in s.grants
        )
        |> repo().one()
      end

      defoverridable grant_for_guard: 2
    end
  end
end
