defmodule Shopifex.Plug.ShopifySession do
  import Plug.Conn
  import Phoenix.Controller
  require Logger

  def init(options) do
    # initialize options
    options
  end

  def call(conn, _) do
    token = get_token_from_conn(conn) || Guardian.Plug.current_token(conn)

    case Shopifex.Guardian.resource_from_token(token) do
      {:ok, shop, claims} ->
        locale = get_locale(conn, claims)
        host = get_host(conn, claims)

        Shopifex.Plug.build_session(conn, shop, host, locale)

      _ ->
        initiate_new_session(conn)
    end
  end

  defp get_token_from_conn(%Plug.Conn{params: %{"token" => token}}), do: token

  defp get_token_from_conn(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      [] -> nil
      ["Bearer " <> token | []] -> token
      _ -> nil
    end
  end

  defp initiate_new_session(conn) do
    expected_hmac = Shopifex.Plug.build_hmac(conn)
    received_hmac = Shopifex.Plug.get_hmac(conn)

    if expected_hmac == received_hmac do
      conn
      |> do_new_session()
    else
      Logger.info("Invalid HMAC, expected #{expected_hmac}")
      respond_invalid(conn)
    end
  end

  defp do_new_session(conn = %{params: %{"shop" => shop_url}}) do
    case Shopifex.Shops.get_shop_by_url(shop_url) do
      nil ->
        redirect_to_install(conn, shop_url)

      shop ->
        locale = get_locale(conn)
        host = get_host(conn)

        Shopifex.Plug.build_session(conn, shop, host, locale)
    end
  end

  defp redirect_to_install(conn, shop_url) do
    Logger.info("Initiating shop installation for #{shop_url}")

    install_url =
      "https://#{shop_url}/admin/oauth/authorize?client_id=#{Application.fetch_env!(:shopifex, :api_key)}&scope=#{Application.fetch_env!(:shopifex, :scopes)}&redirect_uri=#{Application.fetch_env!(:shopifex, :redirect_uri)}"

    conn
    |> redirect(external: install_url)
    |> halt()
  end

  defp respond_invalid(conn) do
    web_module = get_web_module(Application.get_env(:shopifex, :custom_select_store, false))

    conn
    |> put_view(web_module.AuthView)
    |> put_layout({web_module.LayoutView, "app.html"})
    |> render("select-store.html")
    |> halt()
  end

  defp get_web_module(true),
    do: Application.get_env(:shopifex, :web_module)

  defp get_web_module(_),
    do: ShopifexWeb

  defp get_locale(conn, token_claims \\ %{})
  defp get_locale(%Plug.Conn{params: %{"locale" => locale}}, _token_claims), do: locale

  defp get_locale(_conn, token_claims),
    do: Map.get(token_claims, "loc", Application.get_env(:shopifex, :default_locale, "en"))

  defp get_host(conn, token_claims \\ %{})
  defp get_host(%Plug.Conn{params: %{"host" => host}}, _token_claims), do: host

  defp get_host(_conn, token_claims),
    do: Map.get(token_claims, "host")
end
