defmodule ShopifexWeb.Routes do
  defmacro pipelines do
    quote do
      pipeline :shopify_browser do
        plug(:accepts, ["html"])
        plug(:fetch_session)
        plug(Shopifex.Plug.FetchFlash)
        plug(:protect_from_forgery)
        plug(:put_secure_browser_headers)
        plug(Shopifex.Plug.LoadInIframe)
      end

      pipeline :shopify_session do
        plug(Shopifex.Plug.ShopifySession)
      end

      pipeline :shopify_entrypoint do
        plug(Shopifex.Plug.ShopifyEntrypoint)
      end

      pipeline :shopify_webhook do
        plug(Shopifex.Plug.ShopifyWebhook)
      end

      pipeline :admin_links do
        plug(:accepts, ["json"])
        plug(:fetch_session)
        plug(Shopifex.Plug.FetchFlash)
        plug(Shopifex.Plug.LoadInIframe)
      end
    end
  end

  defmacro shopifex_admin() do
    quote do
      scope "/", ShopifexWeb do
        pipe_through([:shopify_browser])
        resources("/plans", PlanController)
        resources("/grants", GrantController)
      end
    end
  end

  defmacro auth_routes(app_web_module \\ ShopifexWeb) do
    quote do
      scope "/auth", unquote(app_web_module) do
        pipe_through([:shopify_browser, :shopify_entrypoint])
        get("/", AuthController, :auth)
        get("/install", AuthController, :install)
        get("/update", AuthController, :update)
      end
    end
  end

  defmacro payment_routes(app_web_module \\ ShopifexWeb) do
    quote do
      scope "/payment", unquote(app_web_module) do
        pipe_through([:shopify_browser, :shopify_session])

        get("/show-plans", PaymentController, :show_plans)
        post("/select-plan", PaymentController, :select_plan)
        get("/complete", PaymentController, :complete_payment)
      end
    end
  end
end
