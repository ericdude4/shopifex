defmodule Shopifex.Plug.ShopifySessionTest do
  use ExUnit.Case, async: true
  use Plug.Test

  test "redirect location preserves parameters" do
    Application.put_env(:shopifex, :shop_schema, %{})
    result = conn(:get, "/?shop=store", %{})
    |> Map.put(:private, %{phoenix_flash: %{shop: ""}})
    |> Shopifex.Plug.ShopifySession.call(%{})

    assert result.halted
    assert result.status == 302
    assert Plug.Conn.get_resp_header(result, "location") == ["/auth?shop=store"]
  end

end
