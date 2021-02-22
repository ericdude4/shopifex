defmodule ShopifexWeb.PageControllerTest do
  use ShopifexWeb.ConnCase

  test "GET / redirects to install", %{conn: conn} do
    conn = get(conn, "/")
    assert html_response(conn, 302) =~ "redirected"
  end
end
