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

      def confirm(conn, params) do
        redirect(conn,
          external:
            "https://localhost:4000/admin/apps/#{Application.fetch_env!(:shopifex, :api_key)}"
        )
      end
    end
  end
end
