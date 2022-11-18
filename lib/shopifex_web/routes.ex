defmodule ShopifexWeb.Routes do
  @moduledoc """
  Provides macros for easily responding to Shopify requests within your Shopifex router.

  ## pipelines
  Call the `pipelines` macro in your router to inject some standard router pipelines into your router module.
  These pipelines can be used for responding to webhooks, admin links, proxy requests, and requests to load your app within the Shopify admin.

  ## auth routes
  Call the `auth_routes` macro in your router to inject the standard Shopify app routes which your app will need.
  This includes routes for loading the app in Shopfiy the admin, app installation and app updates.

  ## payment routes
  Call the `payment_routes` macro in your router to inject the routes required by the Shopifex PaymentGuard system.
  """

  @doc """
  Injects the following Shopify router pipelines into your Shopifex application's router.

  - `:shopify_session`: Validates request (HMAC header/param or token param) and makes session information available via Shopifex.Plug API. Also removes iFrame blocking headers so app can render in Shopify admin.
  - `:shopify_webhook`: Validates Shopify webhook requests HMAC and makes session information available via Shopifex.Plug API.
  - `:shopify_admin_link`: Validates Shopify admin link & bulk action link requests and makes session information available via Shopifex.Plug API. Also removes iFrame blocking headers so app can render in Shopify admin.
  - `:shopify_api`: Ensures that a valid Shopify session token or Shopifex token are present in Authorization header. Useful for async requests between your SPA front end and Shopifex backend.
  - `:shopifex_browser`: Same as your normal :browser pipeline, except it calls Shopifex.Plug.LoadInIframe.
  - `:shopify_embedded`: Sets Content-Security-Policy headers to restrict app loading to within the Shopify admin. Read more: https://shopify.dev/apps/store/security/iframe-protection#embedded-apps
  """
  defmacro pipelines() do
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
        plug(Shopifex.Plug.EnsureScopes)
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

      pipeline :shopify_proxy do
        plug(:fetch_session)
        plug(Shopifex.Plug.FetchFlash)
        plug(Shopifex.Plug.ValidateHmac)
      end

      pipeline :shopify_admin_link do
        plug(:accepts, ["json"])
        plug(:fetch_session)
        plug(Shopifex.Plug.FetchFlash)
        plug(Shopifex.Plug.LoadInIframe)
        plug(Shopifex.Plug.ShopifyWebhook)
        plug(Shopifex.Plug.EnsureScopes)
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

      pipeline :shopifex_api do
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

      pipeline :shopify_embedded do
        plug(Shopifex.Plug.SetCSPHeader)
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

  defmacro payment_routes(controller \\ ShopifexWeb.PaymentController, opts \\ []) do
    # TODO: make embedded default in v3+
    payment_pages_pipe_through =
      if opts[:shopify_embedded] do
        [:shopifex_browser, :shopify_session, :shopify_embedded]
      else
        [:shopifex_browser, :shopify_session]
      end

    quote do
      scope "/payment" do
        pipe_through(unquote(payment_pages_pipe_through))

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
