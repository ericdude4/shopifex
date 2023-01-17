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
  """
  @callback auth(conn :: Plug.Conn.t(), params :: Plug.Conn.params()) :: Plug.Conn.t()

  @optional_callbacks after_install: 3, after_update: 3, insert_shop: 1, auth: 2

  defmacro __using__(_opts) do
    quote do
      @behaviour ShopifexWeb.AuthController

      require Logger

      @impl ShopifexWeb.AuthController
      def auth(conn, _) do
        path_prefix = Application.get_env(:shopifex, :path_prefix, "")

        conn
        |> redirect(to: path_prefix <> "/?token=" <> Guardian.Plug.current_token(conn))
      end

      def initialize_installation(conn, %{"shop" => shop_url} = params) do
        shop_url = String.trim_trailing(shop_url, "/")

        if Regex.match?(~r/^.*\.myshopify\.com/, shop_url) do
          # check if store is in the system already:
          case Shopifex.Shops.get_shop_by_url(shop_url) do
            nil ->
              Logger.info("Initiating shop installation for #{shop_url}")

              install_url =
                "https://#{shop_url}/admin/oauth/authorize?client_id=#{Application.fetch_env!(:shopifex, :api_key)}&scope=#{Application.fetch_env!(:shopifex, :scopes)}&redirect_uri=#{Application.fetch_env!(:shopifex, :redirect_uri)}&state=#{params["state"]}"

              conn
              |> redirect(external: install_url)

            shop ->
              Logger.info("Initiating shop reinstallation for #{shop_url}")

              reinstall_url =
                "https://#{shop_url}/admin/oauth/authorize?client_id=#{Application.fetch_env!(:shopifex, :api_key)}&scope=#{Application.fetch_env!(:shopifex, :scopes)}&redirect_uri=#{Application.fetch_env!(:shopifex, :reinstall_uri)}&state=#{params["state"]}"

              conn
              |> redirect(external: reinstall_url)
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
      def after_install(conn, shop, _state) do
        redirect(conn,
          external:
            "https://#{Shopifex.Shops.get_url(shop)}/admin/apps/#{Application.fetch_env!(:shopifex, :api_key)}"
        )
      end

      @impl ShopifexWeb.AuthController
      def insert_shop(shop) do
        Shopifex.Shops.create_shop(shop)
      end

      def install(conn, %{"code" => code, "shop" => shop_url} = params) do
        state = Map.get(params, "state", "")
        url = "https://#{shop_url}/admin/oauth/access_token"

        case(
          HTTPoison.post(
            url,
            Jason.encode!(%{
              client_id: Application.fetch_env!(:shopifex, :api_key),
              client_secret: Application.fetch_env!(:shopifex, :secret),
              code: code
            }),
            "Content-Type": "application/json",
            Accept: "application/json"
          )
        ) do
          {:ok, response} ->
            params =
              response.body
              |> Jason.decode!(keys: :atoms)
              |> Map.put(:url, shop_url)

            params = Map.put(params, Shopifex.Shops.get_scope_field(), params[:scope])

            shop = insert_shop(params)

            Shopifex.Shops.configure_webhooks(shop)

            after_install(conn, shop, state)

          error ->
            raise(Shopifex.InstallError, message: "Installation failed for shop #{shop_url}")
        end
      end

      @impl ShopifexWeb.AuthController
      def after_update(conn, shop, _state) do
        redirect(conn,
          external:
            "https://#{Shopifex.Shops.get_url(shop)}/admin/apps/#{Application.fetch_env!(:shopifex, :api_key)}"
        )
      end

      def update(conn, %{"code" => code, "shop" => shop_url} = params) do
        state = Map.get(params, "state", "")
        url = "https://#{shop_url}/admin/oauth/access_token"

        case(
          HTTPoison.post(
            url,
            Jason.encode!(%{
              client_id: Application.fetch_env!(:shopifex, :api_key),
              client_secret: Application.fetch_env!(:shopifex, :secret),
              code: code
            }),
            "Content-Type": "application/json",
            Accept: "application/json"
          )
        ) do
          {:ok, response} ->
            params = Jason.decode!(response.body, keys: :atoms)

            params = Map.put(params, Shopifex.Shops.get_scope_field(), params[:scope])

            shop =
              shop_url
              |> Shopifex.Shops.get_shop_by_url()
              |> Shopifex.Shops.update_shop(params)

            Shopifex.Shops.configure_webhooks(shop)

            after_update(conn, shop, state)

          error ->
            raise(Shopifex.UpdateError, message: "Update failed for shop #{shop_url}")
        end
      end

      defoverridable after_install: 3, after_update: 3, insert_shop: 1, auth: 2
    end
  end
end
