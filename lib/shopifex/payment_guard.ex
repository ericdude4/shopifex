defmodule Shopifex.PaymentGuard do
  defmacro __using__(_opts) do
    quote do
      import Ecto.Query, warn: false

      def payment_schema, do: Application.fetch_env!(:shopifex, :payment_schema)
      def repo, do: Application.fetch_env!(:shopifex, :repo)

      @doc """
      Returns a payment record which grants access to the payment guard or nil
      """
      def payment_for_guard(shop, identifier) do
        from(s in payment_schema(),
          where: s.shop_id == ^shop.id,
          where: s.identifier == ^identifier
        )
        |> repo().one()
      end

      defoverridable payment_for_guard: 2
    end
  end
end
