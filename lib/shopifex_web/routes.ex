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

  - `:shopifex_browser`: Same as your normal :browser pipeline, except it calls Shopifex.Plug.LoadInIframe, which removes the `x-frame-options` header and the `frame-ancestors 'self'` CSP directive that `put_secure_browser_headers` sets.
  - `:managed_install`: Runs `Shopifex.Plug.ManagedInstall` — verifies Shopify's `id_token`, exchanges it for an expiring offline access token, and builds the session. Included in `auth_routes/1` before `:shopify_session`.
  - `:shopify_session`: Verifies the App Bridge session token (`id_token`), or the legacy install HMAC, and makes session information available via Shopifex.Plug API. No-ops when an earlier `:managed_install` already loaded the shop. Also removes iFrame blocking headers so app can render in Shopify admin.
  - `:validate_install_hmac`: Runs `Shopifex.Plug.ValidateHmac` only. Used by the legacy OAuth `/auth/install` and `/auth/update` routes, which verify the query HMAC without loading a shop into the session.
  - `:shopify_webhook`: Validates Shopify webhook requests HMAC and makes session information available via Shopifex.Plug API.
  - `:shopify_proxy`: Validates Shopify App proxy requests (signed with `signature`, not `hmac`, and `require_timestamp: true`) via `Shopifex.Plug.ValidateHmac`, then resolves the shop with `Shopifex.Plug.LoadProxyShop`.
  - `:shopify_admin_link`: Validates Shopify admin link & bulk action link requests and makes session information available via Shopifex.Plug API. Also removes iFrame blocking headers so app can render in Shopify admin.
  - `:shopify_api`: Ensures that a valid Shopify App Bridge session token (`id_token`) is present in the Authorization header. Useful for async requests between your SPA front end and Shopifex backend.
  - `:shopifex_api`: Alias of `:shopify_api` (same `Shopifex.Plug.ShopifyApiAuth` behind CORS + JSON), under the `shopifex_`-prefixed name.
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

      pipeline :managed_install do
        plug(Shopifex.Plug.ManagedInstall)
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
        # App-proxy requests always carry a `timestamp`; require it so a signed
        # proxy URL can't be replayed indefinitely.
        plug(Shopifex.Plug.ValidateHmac, require_timestamp: true)
        plug(Shopifex.Plug.LoadProxyShop)
      end

      pipeline :shopify_admin_link do
        plug(:accepts, ["json"])
        plug(:fetch_session)
        plug(Shopifex.Plug.FetchFlash)
        plug(Shopifex.Plug.LoadInIframe)
        # Admin/bulk-action links are GETs signed like an app load; verify the
        # query HMAC (and reject a stale timestamp), and resolve the shop from
        # the signed query rather than the webhook body path.
        plug(Shopifex.Plug.ShopifyWebhook, mode: :admin_link)
        plug(Shopifex.Plug.EnsureScopes)
      end

      pipeline :shopify_api do
        plug(CORSPlug, origin: "*")
        plug(:accepts, ["json"])
        plug(Shopifex.Plug.ShopifyApiAuth)
      end

      pipeline :shopifex_api do
        plug(CORSPlug, origin: "*")
        plug(:accepts, ["json"])
        plug(Shopifex.Plug.ShopifyApiAuth)
      end

      pipeline :shopify_embedded do
        plug(Shopifex.Plug.SetCSPHeader)
      end
    end
  end

  defmacro auth_routes(controller \\ ShopifexWeb.AuthController) do
    quote do
      scope "/auth" do
        # Managed installation (the default for new embedded apps): `:managed_install`
        # runs token exchange from Shopify's per-request `id_token` and builds the
        # session; `:shopify_session` then no-ops when the shop is already loaded, or
        # handles the legacy OAuth/HMAC fallback when no `id_token` is present.
        pipe_through([:shopifex_browser, :managed_install, :shopify_session])
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
    # Embedded (CSP-protected) is the default as of v3. Pass
    # `shopify_embedded: false` to opt out for a legacy non-embedded app.
    payment_pages_pipe_through =
      if Keyword.get(opts, :shopify_embedded, true) do
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

  @doc """
  Generate a live session with the current_shop and session token assigned. All other
  options are passed through to `live_session`.
  """
  @spec shopifex_live_session(atom, opts :: Keyword.t()) :: Macro.t()
  defmacro shopifex_live_session(session_name, opts \\ [], do: block) do
    quote do
      shopifex_live_session_opts = unquote(opts) |> ShopifexWeb.LiveSession.opts()

      Phoenix.LiveView.Router.live_session unquote(session_name), shopifex_live_session_opts do
        unquote(block)
      end
    end
  end
end
