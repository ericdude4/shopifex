defmodule ShopifexWeb.AuthController do
  defmacro __using__(_opts) do
    quote do
      require Logger

      # get authorization token for the shop and save the shop in the DB
      def auth(conn, %{"shop" => shop_url}) do
        if Regex.match?(~r/^.*\.myshopify\.com/, shop_url) do
          conn = put_flash(conn, :shop_url, shop_url)
          # check if store is in the system already:
          case Shopifex.Shops.get_shop_by_url(shop_url) do
            nil ->
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
                conn
                |> put_flash(:shop, shop)
                |> redirect(to: "/")
              else
                send_resp(conn, 403, "Invalid HMAC")
              end
          end
        else
          conn
          |> put_view(ShopifexWeb.AuthView)
          |> put_flash(:error, "Invalid shop URL")
          |> render("select-store.html")
        end
      end

      def auth(conn, _) do
        conn
        |> put_view(ShopifexWeb.AuthView)
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
    end
  end
end
