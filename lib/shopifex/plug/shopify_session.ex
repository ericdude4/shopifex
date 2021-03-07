defmodule Shopifex.Plug.ShopifySession do
  import Plug.Conn
  import Phoenix.Controller
  require Logger

  def init(options) do
    # initialize options
    options
  end

  def call(conn, _) do
    token = get_token_from_conn(conn)

    case Shopifex.Guardian.resource_from_token(token) do
      {:ok, shop, _claims} ->
        put_shop_in_session(conn, shop)

      _ ->
        initiate_new_session(conn)
    end
  end

  defp get_token_from_conn(%Plug.Conn{params: %{"session_token" => session_token}}),
    do: session_token

  defp get_token_from_conn(%Plug.Conn{params: %{"token" => token}}), do: token

  defp get_token_from_conn(_), do: nil

  defp initiate_new_session(conn = %{params: %{"hmac" => hmac}}) do
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
      |> do_new_session()
    else
      respond_invalid(conn)
    end
  end

  defp initiate_new_session(conn), do: respond_invalid(conn)

  defp do_new_session(conn = %{params: %{"shop" => shop_url}}) do
    case Shopifex.Shops.get_shop_by_url(shop_url) do
      nil -> redirect_to_install(conn, shop_url)
      shop -> put_shop_in_session(conn, shop)
    end
  end

  defp redirect_to_install(conn, shop_url) do
    Logger.info("Initiating shop installation for #{shop_url}")

    install_url =
      "https://#{shop_url}/admin/oauth/authorize?client_id=#{
        Application.fetch_env!(:shopifex, :api_key)
      }&scope=#{Application.fetch_env!(:shopifex, :scopes)}&redirect_uri=#{
        Application.fetch_env!(:shopifex, :redirect_uri)
      }"

    conn
    |> redirect(external: install_url)
    |> halt()
  end

  def put_shop_in_session(conn, shop) do
    # Create a new token right away for the next request
    {:ok, token, claims} = Shopifex.Guardian.encode_and_sign(shop)

    conn
    |> Guardian.Plug.put_current_resource(shop)
    |> Guardian.Plug.put_current_claims(claims)
    |> Guardian.Plug.put_current_token(token)
    |> Plug.Conn.put_private(:shop_url, shop.url)
    |> Plug.Conn.put_private(:shop, shop)
  end

  defp respond_invalid(conn) do
    conn
    |> put_view(ShopifexWeb.AuthView)
    |> put_layout({ShopifexWeb.LayoutView, "app.html"})
    |> render("select-store.html")
    |> halt()
  end
end
