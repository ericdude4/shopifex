defmodule Shopifex.Plug.ShopifySessionTest do
  use ExUnit.Case, async: true
  use Plug.Test

  setup do
    shop = %{url: "shopifex.myshopify.com", scope: "orders", access_token: "asdf1234"}

    {:ok, shop}
  end

  test "redirect location preserves parameters" do
    result =
      conn(:get, "/?shop=store", %{})
      |> Map.put(:private, %{phoenix_flash: %{shop: ""}})
      |> Shopifex.Plug.ShopifySession.call(%{})

    assert result.halted
    assert result.status == 302
    assert Plug.Conn.get_resp_header(result, "location") == ["/auth?shop=store"]
  end
end
