defmodule ShopifexWeb.Routes do
  defmacro pipelines do
    quote do
      pipeline :shopify_browser do
        plug(:accepts, ["html"])
        plug(:fetch_session)
        plug(Shopifex.Plug.FetchFlash)
        plug(:put_secure_browser_headers)
        plug(Shopifex.Plug.LoadInIframe)
      end

      pipeline :shopify_session do
        plug(Shopifex.Plug.ShopifySession)
      end

      pipeline :validate_hmac do
        plug(Shopifex.Plug.ValidateHmac)
      end

      pipeline :shopify_webhook do
        plug(:fetch_session)
        plug(Shopifex.Plug.FetchFlash)
        plug(Shopifex.Plug.ShopifyWebhook)
      end

      pipeline :admin_links do
        plug(:accepts, ["json"])
        plug(:fetch_session)
        plug(Shopifex.Plug.FetchFlash)
        plug(Shopifex.Plug.LoadInIframe)
      end

      pipeline :shopify_api do
        plug(CORSPlug, origin: "*")
        plug(:accepts, ["json"])

        plug(
          Guardian.Plug.Pipeline,
          module: Shopifex.Guardian,
          error_handler: ShopifexWeb.AuthErrorHandler
        )

        plug(Guardian.Plug.VerifyHeader)
        plug(Guardian.Plug.EnsureAuthenticated)
        plug(Guardian.Plug.LoadResource)
      end
    end
  end

  defmacro auth_routes(app_web_module \\ ShopifexWeb) do
    quote do
      scope "/auth", unquote(app_web_module) do
        pipe_through([:shopify_browser, :shopify_session])
        get("/", AuthController, :auth)
      end

      scope "/auth", unquote(app_web_module) do
        pipe_through([:shopify_browser, :validate_hmac])
        get("/install", AuthController, :install)
        get("/update", AuthController, :update)
      end

      scope "/initialize-installation", unquote(app_web_module) do
        pipe_through([:shopify_browser])
        get("/", AuthController, :initialize_installation)
      end
    end
  end

  defmacro payment_routes(app_web_module \\ ShopifexWeb) do
    quote do
      scope "/payment", unquote(app_web_module) do
        pipe_through([:shopify_browser, :shopify_session])

        get("/show-plans", PaymentController, :show_plans)
        post("/select-plan", PaymentController, :select_plan)
      end

      scope "/payment", unquote(app_web_module) do
        pipe_through([:shopify_browser])
        get("/complete", PaymentController, :complete_payment)
      end

      scope "/payment", unquote(app_web_module) do
        pipe_through([:shopify_api])

        scope "/api" do
          options("/select-plan", PaymentController, :select_plan)
          post("/select-plan", PaymentController, :select_plan)
        end
      end
    end
  end
end
