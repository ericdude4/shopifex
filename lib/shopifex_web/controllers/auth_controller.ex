defmodule ShopifexWeb.AuthController do
  @moduledoc """
  You can use this module inside of another controller to handle initial iFrame load and shop installation

  Example:

  ```elixir
  defmodule MyAppWeb.AuthController do
    use MyAppWeb, :controller
    use ShopifexWeb.AuthController

    # Thats it! Validation, installation are now handled for you :)
  end
  ```
  """
  @type shop :: %{access_token: String.t(), scope: String.t(), url: String.t()}

  @doc """
  An optional callback called after the installation is completed, the shop is
  persisted in the database and webhooks are registered. By default, this function
  redirects the user to the app within their Shopify admin panel.

  ## Example

      @impl true
      def after_install(conn, shop, oauth_state) do
        # send yourself an e-mail about shop installation

        # follow default behaviour.
        super(conn, shop, oauth_state)
      end
  """
  @callback after_install(Plug.Conn.t(), shop(), oauth_state :: String.t()) :: Plug.Conn.t()

  @doc """
  An optional callback called after the oauth update is completed. By default,
  this function redirects the user to the app within their Shopify admin panel.

  ## Example

      @impl true
      def after_update(conn, shop, oauth_state) do
        # do some work related to oauth_state

        # follow default behaviour.
        super(conn, shop, oauth_state)
      end
  """
  @callback after_update(Plug.Conn.t(), shop(), oauth_state :: String.t()) :: Plug.Conn.t()

  @doc """
  An optional callback which is called after the shop data has been retrieved from
  Shopify API. This function should persist the shop data and return a shop record.

  ## Example

      @impl true
      def insert_shop(shop) do
        # make sure there is only one store in the database because we don't have
        # a unique index on the url column for some reason.

        case Shopifex.Shops.get_shop_by_url(shop.url) do
          nil -> super(shop)
          shop -> shop
        end
      end
  """
  @callback insert_shop(shop()) :: shop()

  @doc """
  An optional callback which you can use to override how your app is rendered on
  initial load. If you are building a server-rendered app, you might just want
  to redirect to your index page. If you are building an externally hosted SPA,
  you probably want to redirect to the Shopify admin link for your app.

  Externally hosted SPA's will likely only hit this route on install.

  The default implementation redirects to `path_prefix <> "/"`. When the
  request carries an `id_token` (an App Bridge embedded load) it forwards only
  the embedded-context params (`shop`, `host`, `embedded`, `locale`,
  `id_token`) so the landing route can authenticate via the still-valid
  `id_token`. When `id_token` is absent — a legacy non-embedded app with no
  App Bridge — it forwards the complete original query Shopify signed
  (including `hmac` and `timestamp`) so the landing route's `:shopify_session`
  has something to re-verify instead of falling through to the store selector.
  """
  @callback auth(conn :: Plug.Conn.t(), params :: Plug.Conn.params()) :: Plug.Conn.t()

  @optional_callbacks after_install: 3, after_update: 3, insert_shop: 1, auth: 2

  defmacro __using__(_opts) do
    quote do
      @behaviour ShopifexWeb.AuthController

      require Logger

      @impl ShopifexWeb.AuthController
      def auth(conn, params) do
        path_prefix = Application.get_env(:shopifex, :path_prefix, "")

        # A server 302 is a top-level iframe navigation, so — unlike App Bridge
        # `fetch`es — it does NOT inherit the `id_token`, and third-party cookies
        # are blocked, so identity is not carried implicitly to the landing route.
        query =
          if Map.has_key?(params, "id_token") do
            # Forward the embedded-context params: per Shopify's docs App Bridge
            # needs `shop` and `host` to (re)initialize and acquire a session
            # token on the landing page, and forwarding the still-valid
            # `id_token` lets that route's `:shopify_session` authenticate this
            # immediate hop without a bounce.
            params
            |> Map.take(["shop", "host", "embedded", "locale", "id_token"])
            |> URI.encode_query()
          else
            # Legacy non-embedded app (no App Bridge, so no `id_token`). Forward
            # Shopify's complete original query — including `hmac` and
            # `timestamp` — so the landing route's `:shopify_session` has
            # something to re-verify; otherwise it finds nothing to
            # authenticate against and renders the store selector.
            conn
            |> Plug.Conn.fetch_query_params()
            |> Map.fetch!(:query_params)
            |> URI.encode_query()
          end

        # (Whatever route you redirect to must sit behind a `:shopify_session`
        # pipeline for this to work.)
        to = path_prefix <> "/" <> if(query == "", do: "", else: "?" <> query)

        redirect(conn, to: to)
      end

      def initialize_installation(conn, %{"shop" => shop_url} = params) do
        if Shopifex.ShopDomain.valid?(shop_url) do
          # A bracket-syntax `state[a]=b` parses to a map, which
          # `URI.encode_query/1` rejects; only a string state is forwarded.
          state = if is_binary(params["state"]), do: params["state"], else: nil

          # The installation case and reinstallation case share the same URL, and query parameters,
          # except for the value of of the redirect_uri
          url = fn redirect_uri ->
            build_external_url(["https://", shop_url, "/admin/oauth/authorize"], %{
              client_id: Application.fetch_env!(:shopifex, :api_key),
              scope: Application.fetch_env!(:shopifex, :scopes),
              redirect_uri: redirect_uri,
              state: state
            })
          end

          # check if store is in the system already:
          case Shopifex.Shops.get_shop_by_url(shop_url) do
            nil ->
              Logger.info("Initiating shop installation for #{shop_url}")
              install_url = url.(Application.fetch_env!(:shopifex, :redirect_uri))
              redirect(conn, external: install_url)

            shop ->
              Logger.info("Initiating shop reinstallation for #{shop_url}")
              reinstall_url = url.(Application.fetch_env!(:shopifex, :reinstall_uri))
              redirect(conn, external: reinstall_url)
          end
        else
          conn
          |> put_view(ShopifexWeb.AuthHTML)
          |> put_root_layout(html: false)
          |> put_layout(html: {ShopifexWeb.Layouts, :app})
          |> put_flash(:error, "Invalid shop URL")
          |> render("select_store.html")
        end
      end

      @impl ShopifexWeb.AuthController
      def after_install(conn, shop, _state) do
        redirect(conn, external: admin_apps_url(shop))
      end

      @impl ShopifexWeb.AuthController
      def insert_shop(shop) do
        Shopifex.Shops.create_shop(shop)
      end

      def install(conn, %{"code" => code, "shop" => shop_url} = params) do
        state = Map.get(params, "state", "")
        url = build_external_url(["https://", shop_url, "/admin/oauth/access_token"])

        # `expiring=1` is required for public apps created on or after
        # 2026-04-01, and requests the expiring-token lifecycle fields
        # (`expires_in`, `refresh_token`, `refresh_token_expires_in`):
        # https://shopify.dev/changelog/expiring-offline-access-tokens-required-for-public-apps-april-1-2026
        body =
          URI.encode_query(%{
            "client_id" => Application.fetch_env!(:shopifex, :api_key),
            "client_secret" => Application.fetch_env!(:shopifex, :secret),
            "code" => code,
            "expiring" => "1"
          })

        req_opts =
          [
            body: body,
            headers: [{"content-type", "application/x-www-form-urlencoded"}]
          ] ++ Application.get_env(:shopifex, :req_options, [])

        case Req.post(url, req_opts) do
          {:ok, %{status: 200, body: response_body}} ->
            shop = insert_shop(Shopifex.TokenResponse.shop_attrs(shop_url, response_body))

            Shopifex.Shops.configure_webhooks(shop)

            after_install(conn, shop, state)

          _error ->
            raise(Shopifex.InstallError, message: "Installation failed for shop #{shop_url}")
        end
      end

      @impl ShopifexWeb.AuthController
      def after_update(conn, shop, _state) do
        redirect(conn, external: admin_apps_url(shop))
      end

      def update(conn, %{"code" => code, "shop" => shop_url} = params) do
        state = Map.get(params, "state", "")
        url = build_external_url(["https://", shop_url, "/admin/oauth/access_token"])

        body =
          URI.encode_query(%{
            "client_id" => Application.fetch_env!(:shopifex, :api_key),
            "client_secret" => Application.fetch_env!(:shopifex, :secret),
            "code" => code,
            "expiring" => "1"
          })

        req_opts =
          [
            body: body,
            headers: [{"content-type", "application/x-www-form-urlencoded"}]
          ] ++ Application.get_env(:shopifex, :req_options, [])

        case Req.post(url, req_opts) do
          {:ok, %{status: 200, body: response_body}} ->
            attrs = Shopifex.TokenResponse.shop_attrs(shop_url, response_body)

            shop =
              shop_url
              |> Shopifex.Shops.get_shop_by_url()
              |> Shopifex.Shops.update_shop(attrs)

            Shopifex.Shops.configure_webhooks(shop)

            after_update(conn, shop, state)

          _error ->
            raise(Shopifex.UpdateError, message: "Update failed for shop #{shop_url}")
        end
      end

      defoverridable after_install: 3, after_update: 3, insert_shop: 1, auth: 2

      defp admin_apps_url(shop) do
        shop_url = Shopifex.Shops.get_url(shop)
        api_key = Application.fetch_env!(:shopifex, :api_key)

        build_external_url(["https://", shop_url, "/admin/apps", api_key])
      end

      defp build_external_url(path, query_params \\ %{}) do
        base = Path.join(path)

        case URI.encode_query(query_params) do
          "" -> base
          query -> base <> "?" <> query
        end
      end
    end
  end
end
