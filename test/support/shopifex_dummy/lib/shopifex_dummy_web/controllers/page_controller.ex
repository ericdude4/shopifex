defmodule ShopifexDummyWeb.PageController do
  use ShopifexDummyWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
