defmodule ShopifexWeb.PageControllerTest do
  use ShopifexWeb.ConnCase

  test "GET / without session renders install", %{conn: conn} do
    conn = get(conn, "/")
    assert html_response(conn, 200) =~ "Install"
  end
end
