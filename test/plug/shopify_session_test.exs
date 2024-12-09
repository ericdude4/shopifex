defmodule Shopifex.Plug.ShopifySessionTest do
  use ShopifexWeb.ConnCase

  test "responds unauthorized when request content type is json" do
    conn =
      build_conn(:get, "?locale=fr")
      |> Map.merge(%{private: %{phoenix_format: "json"}})
      |> Plug.Conn.fetch_query_params()
      |> Shopifex.Plug.ShopifySession.call([])

    assert %{"message" => "Unauthorized"} = json_response(conn, 403)
  end

  describe "authorized requests" do
    setup do
      conn =
        build_conn(:get, "?locale=fr")
        |> Plug.Conn.fetch_query_params()

      {:ok, conn: conn}
    end

    setup [:shop_in_session]

    test "locale is placed in session with locale parameter", %{conn: conn} do
      Shopifex.Plug.ShopifySession.call(conn, [])

      assert Gettext.get_locale() == "fr"
    end
  end
end
