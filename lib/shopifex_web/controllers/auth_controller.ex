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
  defmacro __using__(_opts) do
    quote do
      require Logger

      # get authorization token for the shop and save the shop in the DB
      # The session parameter indicates that this is an entry point request
      def auth(conn, %{"shop" => shop_url, "session" => _session}) do
        if Regex.match?(~r/^.*\.myshopify\.com/, shop_url) do
          conn = put_flash(conn, :shop_url, shop_url)
          # check if store is in the system already:
          case Shopifex.Shops.get_shop_by_url(shop_url) do
            nil ->
              # If not, prompt user for install
              install_url =
                "https://#{shop_url}/admin/oauth/authorize?client_id=#{
                  Application.fetch_env!(:shopifex, :api_key)
                }&scope=#{Application.fetch_env!(:shopifex, :scopes)}&redirect_uri=#{
                  Application.fetch_env!(:shopifex, :redirect_uri)
                }"

              conn
              |> redirect(external: install_url)

            shop ->
              # If so, place the shop in the session and proceed to the app index
              # This should be an overridable function instead of hard-coded here
              if conn.private.valid_hmac do
                path_prefix = Application.get_env(:shopifex, :path_prefix, "")

                conn
                |> put_flash(:shop, shop)
                |> redirect(to: path_prefix <> "/")
              else
                send_resp(
                  conn,
                  403,
                  "A store was found, but no valid HMAC parameter was provided. Please load this app within the #{
                    shop_url
                  } admin panel."
                )
              end
          end
        else
          conn
          |> put_view(ShopifexWeb.AuthView)
          |> put_layout({ShopifexWeb.LayoutView, "app.html"})
          |> put_flash(:error, "Invalid shop URL")
          |> render("select-store.html")
        end
      end

      def auth(conn, %{"shop" => shop_url}) do
        if Regex.match?(~r/^.*\.myshopify\.com/, shop_url) do
          conn = put_flash(conn, :shop_url, shop_url)
          # check if store is in the system already:
          case Shopifex.Shops.get_shop_by_url(shop_url) do
            nil ->
              Logger.info("Initiating shop installation for #{shop_url}")

              install_url =
                "https://#{shop_url}/admin/oauth/authorize?client_id=#{
                  Application.fetch_env!(:shopifex, :api_key)
                }&scope=#{Application.fetch_env!(:shopifex, :scopes)}&redirect_uri=#{
                  Application.fetch_env!(:shopifex, :redirect_uri)
                }"

              conn
              |> redirect(external: install_url)

            shop ->
              if conn.private.valid_hmac do
                Logger.info("Initiating shop reinstallation for #{shop_url}")

                reinstall_url =
                  "https://#{shop_url}/admin/oauth/request_grant?client_id=#{
                    Application.fetch_env!(:shopifex, :api_key)
                  }&scope=#{Application.fetch_env!(:shopifex, :scopes)}&redirect_uri=#{
                    Application.fetch_env!(:shopifex, :reinstall_uri)
                  }"

                conn
                |> redirect(external: reinstall_url)
              else
                send_resp(
                  conn,
                  403,
                  "A store was found, but no valid HMAC parameter was provided. Please load this app within the #{
                    shop_url
                  } admin panel."
                )
              end
          end
        else
          conn
          |> put_view(ShopifexWeb.AuthView)
          |> put_layout({ShopifexWeb.LayoutView, "app.html"})
          |> put_flash(:error, "Invalid shop URL")
          |> render("select-store.html")
        end
      end

      def auth(conn, _) do
        conn
        |> put_view(ShopifexWeb.AuthView)
        |> put_layout({ShopifexWeb.LayoutView, "app.html"})
        |> render("select-store.html")
      end

      def install(conn = %{private: %{valid_hmac: true}}, %{"code" => code, "shop" => shop_url}) do
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
            shop =
              Jason.decode!(response.body, keys: :atoms)
              |> Map.put(:url, shop_url)
              |> Shopifex.Shops.create_shop()
              |> Shopifex.Shops.configure_webhooks()

            redirect(conn,
              external:
                "https://#{shop_url}/admin/apps/#{Application.fetch_env!(:shopifex, :api_key)}"
            )

          error ->
            IO.inspect(error)
        end
      end

      def update(conn = %{private: %{valid_hmac: true}}, %{"code" => code, "shop" => shop_url}) do
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
            shop = Shopifex.Shops.get_shop_by_url(shop_url)

            Jason.decode!(response.body, keys: :atoms)
            |> Shopifex.Shops.update_shop(shop)
            |> Shopifex.Shops.configure_webhooks()

            redirect(conn,
              external:
                "https://#{shop_url}/admin/apps/#{Application.fetch_env!(:shopifex, :api_key)}"
            )

          error ->
            IO.inspect(error)
        end
      end
    end
  end
end
