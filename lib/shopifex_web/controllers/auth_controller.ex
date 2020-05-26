defmodule ShopifexWeb.AuthController do
  use ShopifexWeb, :controller
  require Logger
  require Protocol

  plug :verify_hmac_url_parameter when action in [:install, :auth]

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
      |> put_flash(:error, "Invalid shop URL")
      |> render("select-store.html")
    end
  end

  def auth(conn, _), do: render(conn, "select-store.html")

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

  defp verify_hmac_url_parameter(conn = %{params: %{"hmac" => hmac}}, _) do
    hmac = String.upcase(hmac)

    query_string =
      String.split(conn.query_string, "&")
      |> Enum.map(fn query ->
        [key, value] = String.split(query, "=")
        {key, value}
      end)
      |> Enum.filter(fn {key, _} ->
        key != "hmac"
      end)
      |> Enum.map(fn {key, value} ->
        "#{key}=#{value}"
      end)
      |> Enum.join("&")

    our_hmac =
      :crypto.hmac(
        :sha256,
        Application.fetch_env!(:shopifex, :secret),
        query_string
      )
      |> Base.encode16()

    if our_hmac == hmac do
      conn
      |> put_private(:valid_hmac, true)
    else
      conn
      |> put_private(:valid_hmac, false)
    end
  end

  defp verify_hmac_url_parameter(conn, _params) do
    conn
    |> put_private(:valid_hmac, false)
  end
end
