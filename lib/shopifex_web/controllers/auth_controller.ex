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
      def after_callback(conn, shop, oauth_state) do
        # send yourself an e-mail about shop installation

        # follow default behaviour.
        super(conn, shop, oauth_state)
      end
  """
  @callback after_callback(Plug.Conn.t(), shop(), params :: map()) :: Plug.Conn.t()

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
      def insert_shop(shop_params) do
        # Override the default behaviour, make sure to call `super` at some point
        super(shop_params)
      end

  """
  @callback insert_shop(params :: shop()) :: shop()

  @doc """
  An optional callback which is called after the shop data has been retrieved from
  Shopify API. This function should persist the shop data and return a shop record.

  ## Example

      @impl true
      def update_shop(shop, shop_params) do
        super(shop, shop_params)
      end

  """
  @callback update_shop(shop(), params :: map()) :: shop()

  @doc """
  An optional callback which you can use to override how your app is rendered on
  initial load. If you are building a server-rendered app, you might just want
  to redirect to your index page. If you are building an externally hosted SPA,
  you probably want to redirect to the Shopify admin link for your app.

  Externally hosted SPA's will likely only hit this route on install.
  """
  @callback auth(conn :: Plug.Conn.t(), params :: Plug.Conn.params()) :: Plug.Conn.t()

  @optional_callbacks after_callback: 3,
                      after_install: 3,
                      after_update: 3,
                      insert_shop: 1,
                      update_shop: 2,
                      auth: 2

  defmacro __using__(_opts) do
    quote do
      import ShopifexWeb.AuthController, only: [embedded_app_uri: 1]

      require Logger

      @behaviour ShopifexWeb.AuthController

      @impl ShopifexWeb.AuthController
      def auth(conn, _) do
        path_prefix = Application.get_env(:shopifex, :path_prefix, "")
        redirect(conn, to: path_prefix <> "/?token=" <> Guardian.Plug.current_token(conn))
      end

      def initialize_installation(conn, %{"shop" => shop_url} = params) do
        if Regex.match?(~r/^.*\.myshopify\.com/, shop_url) do
          # check if store is in the system already:
          case Shopifex.Shops.get_shop_by_url(shop_url) do
            nil ->
              Logger.info("Initiating shop installation for #{shop_url}")

              redirect_to_oauth(conn, shop_url,
                redirect_uri: Application.fetch_env!(:shopifex, :redirect_uri)
              )

            shop ->
              Logger.info("Initiating shop re-installation for #{shop_url}")

              redirect_to_oauth(conn, shop_url,
                redirect_uri: Application.fetch_env!(:shopifex, :reinstall_uri)
              )
          end
        else
          conn
          |> put_view(ShopifexWeb.AuthView)
          |> put_layout({ShopifexWeb.LayoutView, "app.html"})
          |> put_flash(:error, "Invalid shop URL")
          |> render("select-store.html")
        end
      end

      @impl ShopifexWeb.AuthController
      def insert_shop(shop) do
        Shopifex.Shops.create_shop(shop)
      end

      @impl ShopifexWeb.AuthController
      def after_callback(conn, shop, %{} = params) do
        conn
        |> Plug.Conn.assign(:shop, shop)
        |> redirect_to_app({:host, params.host})
      end

      def callback(conn, %{"code" => code, "shop" => shop_url} = params) do
        host = Map.fetch!(params, "host")
        state = Map.get(params, "state", "")

        case Shopifex.OAuth.post_access_token(shop_url, code) do
          {:ok, response} ->
            args = Jason.decode!(response.body, keys: :atoms)

            args =
              args
              |> Map.put(:url, shop_url)
              |> Map.put(Shopifex.Shops.get_scope_field(), args[:scope])

            shop =
              case Shopifex.Shops.get_shop_by_url(shop_url) do
                nil ->
                  insert_shop(args)

                %_{} = shop ->
                  args = Map.drop(args, :url)
                  update_shop(shop, args)
              end

            Shopifex.Shops.configure_webhooks(shop)

            after_callback(conn, shop, %{
              state: state,
              host: host
            })

          error ->
            raise Shopifex.InstallError, message: "Installation failed for shop #{shop_url}"
        end
      end

      @impl ShopifexWeb.AuthController
      def after_install(conn, shop, _state) do
        redirect_to_app(conn, {:shop, shop})
      end

      def install(conn, %{"code" => code, "shop" => shop_url} = params) do
        state = Map.get(params, "state", "")

        case Shopifex.OAuth.post_access_token(shop_url, code) do
          {:ok, response} ->
            params = Jason.decode!(params, keys: :atoms)

            params =
              params
              |> Map.put(:url, shop_url)
              |> Map.put(Shopifex.Shops.get_scope_field(), params[:scope])

            shop = insert_shop(params)

            Shopifex.Shops.configure_webhooks(shop)

            after_install(conn, shop, state)

          error ->
            raise Shopifex.InstallError, message: "Installation failed for shop #{shop_url}"
        end
      end

      @impl ShopifexWeb.AuthController
      def update_shop(%_{} = shop, %{} = params) do
        Shopifex.Shops.update_shop(shop, params)
      end

      @impl ShopifexWeb.AuthController
      def after_update(conn, shop, _state) do
        redirect_to_app(conn, {:shop, shop})
      end

      def update(conn, %{"code" => code, "shop" => shop_url} = params) do
        state = Map.get(params, "state", "")

        case Shopifex.OAuth.post_access_token(shop_url, code) do
          {:ok, response} ->
            params = Jason.decode!(params, keys: :atoms)
            params = Map.put(params, Shopifex.Shops.get_scope_field(), params[:scope])

            shop =
              shop_url
              |> Shopifex.Shops.get_shop_by_url()
              |> update_shop(params)

            Shopifex.Shops.configure_webhooks(shop)

            after_update(conn, shop, state)

          error ->
            raise Shopifex.UpdateError, message: "Update failed for shop #{shop_url}"
        end
      end

      defp redirect_to_app(conn, {:shop, %_{} = shop}) do
        host_url = Shopifex.Shops.get_url(shop)
        redirect_to_app(conn, host_url)
      end

      defp redirect_to_app(conn, {:host, base64_host}) do
        host_url = Base.decode64!(base64_host, padding: false)
        redirect_to_app(conn, host_url)
      end

      defp redirect_to_app(conn, host_url) do
        embedded_app_url =
          host_url
          |> embedded_app_uri()
          |> URI.append_path("/")
          |> URI.to_string()

        redirect(conn, external: embedded_app_url)
      end

      defp redirect_to_oauth(conn, shop_url, opts \\ []) do
        oauth_url = Shopifex.OAuth.oauth_redirect_url(shop_url, opts)

        # Escape the iframe for embedded apps
        # https://shopify.dev/docs/apps/build/authentication-authorization/access-tokens/authorization-code-grant#check-for-and-escape-the-iframe-embedded-apps-only
        if Map.get(conn.params, "embedded") == "1" do
          conn
          |> put_layout(html: {ShopifexWeb.LayoutView, :app})
          |> put_view(ShopifexWeb.PageView)
          |> render("redirect.html", redirect_location: oauth_url, message: "")
        else
          redirect(conn, external: oauth_url)
        end
      end

      defoverridable after_callback: 3,
                     after_install: 3,
                     after_update: 3,
                     insert_shop: 1,
                     update_shop: 2,
                     auth: 2
    end
  end

  @spec embedded_app_uri(String.t()) :: URI.t()
  def embedded_app_uri(host) do
    api_key = Application.fetch_env!(:shopifex, :api_key)
    URI.new!("https://#{host}/apps/#{api_key}")
  end
end
