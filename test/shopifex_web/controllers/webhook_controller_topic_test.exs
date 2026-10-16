defmodule ShopifexDummyWeb.WebhookControllerTopicTest do
  @moduledoc """
  Covers `ShopifexWeb.WebhookController` topic dispatch by invoking the dummy
  controller's plug pipeline directly (the `:shopify_webhook` HMAC pipeline is
  covered separately in `Shopifex.Plug.HmacTest`). The focus is the
  `assign_shopify_topic` plug: a missing `x-shopify-topic` header must fail
  closed with a 400 rather than raise a `MatchError` (→ 500).
  """
  use ExUnit.Case, async: true

  @controller ShopifexDummyWeb.WebhookController

  defp call_action(conn), do: @controller.call(conn, @controller.init(:action))

  test "missing x-shopify-topic header halts with 400 before the action runs" do
    conn = call_action(Plug.Test.conn(:post, "/webhook"))

    assert conn.halted
    assert conn.status == 400
  end

  test "a duplicated x-shopify-topic header also fails closed with 400" do
    conn =
      Plug.Test.conn(:post, "/webhook")
      |> Plug.Conn.put_req_header("x-shopify-topic", "orders/create")
      |> Plug.Conn.put_req_header("x-shopify-topic", "shop/redact")

    # put_req_header replaces, so force the duplicate explicitly.
    conn = %{conn | req_headers: [{"x-shopify-topic", "a"}, {"x-shopify-topic", "b"}]}

    conn = call_action(conn)

    assert conn.halted
    assert conn.status == 400
  end

  test "a single valid topic dispatches to handle_topic/3 (200)" do
    conn =
      Plug.Test.conn(:post, "/webhook")
      |> Plug.Conn.put_req_header("x-shopify-topic", "foo/bar")
      |> call_action()

    assert conn.status == 200
    assert conn.resp_body == "success"
  end
end
