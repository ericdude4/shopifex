defmodule ShopifexDummyWeb.PageController do
  use ShopifexDummyWeb, :controller

  def index(conn, _params) do
    conn
    |> put_view(html: ShopifexDummyWeb.PageHTML)
    |> render("index.html")
  end
end
