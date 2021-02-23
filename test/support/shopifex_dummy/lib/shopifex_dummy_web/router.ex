defmodule ShopifexDummyWeb.Router do
  use ShopifexDummyWeb, :router
  require ShopifexWeb.Routes

  ShopifexWeb.Routes.pipelines()
  ShopifexWeb.Routes.payment_routes(ShopifexDummyWeb)
  ShopifexWeb.Routes.auth_routes(ShopifexDummyWeb)

  scope "/", ShopifexDummyWeb do
    pipe_through([:shopify_browser, :shopify_session])

    get("/", PageController, :index)
  end
end
