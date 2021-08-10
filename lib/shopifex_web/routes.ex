defmodule ShopifexWeb.Routes do
  defmacro pipelines do
    quote do
      pipeline :shopifex_browser do
        plug(:accepts, ["html"])
        plug(:fetch_session)
        plug(:fetch_flash)
        plug(:put_secure_browser_headers)
        plug(Shopifex.Plug.LoadInIframe)
      end

      pipeline :shopify_session do
        plug(Shopifex.Plug.ShopifySession)
        plug(Shopifex.Plug.LoadInIframe)
      end

      pipeline :validate_install_hmac do
        plug(Shopifex.Plug.ValidateHmac)
      end

      pipeline :shopify_webhook do
        plug(:fetch_session)
        plug(Shopifex.Plug.FetchFlash)
        plug(Shopifex.Plug.ShopifyWebhook)
      end

      pipeline :shopify_admin_link do
        plug(:accepts, ["json"])
        plug(:fetch_session)
        plug(Shopifex.Plug.FetchFlash)
        plug(Shopifex.Plug.LoadInIframe)
        plug(Shopifex.Plug.ShopifyWebhook)
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

  defmacro auth_routes(controller \\ ShopifexWeb.AuthController) do
    quote do
      scope "/auth" do
        pipe_through([:shopifex_browser, :shopify_session])
        get("/", unquote(controller), :auth)
      end

      scope "/auth" do
        pipe_through([:shopifex_browser, :validate_install_hmac])
        get("/install", unquote(controller), :install)
        get("/update", unquote(controller), :update)
      end

      scope "/initialize-installation" do
        pipe_through([:shopifex_browser])
        get("/", unquote(controller), :initialize_installation)
      end
    end
  end

  defmacro payment_routes(controller \\ ShopifexWeb.PaymentController) do
    quote do
      scope "/payment" do
        pipe_through([:shopifex_browser, :shopify_session])

        get("/show-plans", unquote(controller), :show_plans)
        post("/select-plan", unquote(controller), :select_plan)
      end

      scope "/payment" do
        pipe_through([:shopifex_browser])
        get("/complete", unquote(controller), :complete_payment)
      end

      scope "/payment" do
        pipe_through([:shopify_api])

        scope "/api" do
          options("/select-plan", unquote(controller), :select_plan)
          post("/select-plan", unquote(controller), :select_plan)
        end
      end
    end
  end
end
