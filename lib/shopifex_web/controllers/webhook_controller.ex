defmodule ShopifexWeb.WebhookController do
  @moduledoc """
  Dispatches verified Shopify webhooks to a handle_topic/3 clause you define in
  your own controller.

  `use ShopifexWeb.WebhookController` wires up an action/2 that calls
  `handle_topic(conn, shop, topic)`, where `topic` comes from the
  `x-shopify-topic` header (a missing or duplicated header is rejected with
  `400`). Add a clause per topic you subscribe to:

  ```elixir
  use ShopifexWeb.WebhookController

  # `app/uninstalled` has no built-in default — handle it yourself.
  def handle_topic(conn, shop, "app/uninstalled") do
    Shopifex.Shops.delete_shop(shop)
    send_resp(conn, 200, "success")
  end
  ```

  ## Built-in GDPR compliance defaults

  This module ships default clauses for Shopify's three mandatory compliance
  (GDPR) topics so a fresh app passes review without extra code:

    * `customers/data_request` — acknowledges with `200` (touches no data).
    * `customers/redact` — acknowledges with `200` (touches no data). Delete
      customer data here if your app stores any.
    * `shop/redact` — deletes the shop record (when one is loaded) and responds
      `200`.

  handle_topic/3 is `defoverridable`. **Defining your own handle_topic/3
  replaces *all* of these defaults**, including the GDPR clauses. To keep them,
  add a catch-all that delegates to super/3:

  ```elixir
  def handle_topic(conn, shop, topic), do: super(conn, shop, topic)
  ```
  """
  defmacro __using__(_opts) do
    quote do
      plug(:assign_shopify_topic)

      # Every genuine Shopify webhook carries exactly one `x-shopify-topic`
      # header, but pattern-matching `[topic]` raised a `MatchError` (→ 500) on a
      # missing or duplicated header. Fail closed with a 400 instead so a
      # malformed request can't crash the endpoint.
      defp assign_shopify_topic(conn, _) do
        case Plug.Conn.get_req_header(conn, "x-shopify-topic") do
          [topic] ->
            Plug.Conn.assign(conn, :shopify_topic, topic)

          _ ->
            require Logger
            Logger.info("Rejecting webhook with missing or duplicate x-shopify-topic header")

            conn
            |> Plug.Conn.send_resp(400, "missing x-shopify-topic header")
            |> Plug.Conn.halt()
        end
      end

      def action(conn, _),
        do: handle_topic(conn, Shopifex.Plug.current_shop(conn), conn.assigns[:shopify_topic])

      # Default handlers for Shopify's mandatory compliance (GDPR) webhooks.
      # These satisfy app-review requirements out of the box: `shop/redact`
      # deletes the shop record, the customer topics acknowledge with 200.
      #
      # `handle_topic/3` is `defoverridable`, so apps can replace these. If you
      # define your own `handle_topic/3` clauses you replace ALL of them — add a
      # catch-all that calls `super(conn, shop, topic)` if you want to keep these
      # compliance defaults.
      def handle_topic(conn, _shop, "customers/data_request"),
        do: Plug.Conn.send_resp(conn, 200, "")

      def handle_topic(conn, _shop, "customers/redact"),
        do: Plug.Conn.send_resp(conn, 200, "")

      def handle_topic(conn, shop, "shop/redact") do
        if shop, do: Shopifex.Shops.delete_shop(shop)
        Plug.Conn.send_resp(conn, 200, "")
      end

      defoverridable handle_topic: 3
    end
  end
end
