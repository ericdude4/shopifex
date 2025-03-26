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
      do_new_session(conn)
    else
      Logger.info("Invalid HMAC, expected #{expected_hmac}")
      respond_invalid(conn)
    end
  end

  defp do_new_session(conn = %{params: %{"shop" => shop_url}}) do
    case Shopifex.Shops.get_shop_by_url(shop_url) do
      nil ->
        conn
        |> redirect(to: "/initialize-installation?#{conn.query_string}")
        |> halt()

      shop ->
        locale = get_locale(conn)
        host = get_host(conn)

        Shopifex.Plug.build_session(conn, shop, host, locale)
    end
  end

  defp respond_invalid(%Plug.Conn{private: %{phoenix_format: "json"}} = conn) do
    conn
    |> put_status(:forbidden)
    |> put_view(ShopifexWeb.AuthView)
    |> render("403.json", message: "Unauthorized")
    |> halt()
  end

  defp respond_invalid(conn) do
    conn
    |> put_view(ShopifexWeb.AuthView)
    |> put_layout({ShopifexWeb.LayoutView, "app.html"})
    |> render("select-store.html")
    |> halt()
  end

  defp get_locale(conn, token_claims \\ %{})
  defp get_locale(%Plug.Conn{params: %{"locale" => locale}}, _token_claims), do: locale

  defp get_locale(_conn, token_claims),
    do: Map.get(token_claims, "loc", Application.get_env(:shopifex, :default_locale, "en"))

  defp get_host(conn, token_claims \\ %{})
  defp get_host(%Plug.Conn{params: %{"host" => host}}, _token_claims), do: host

  defp get_host(_conn, token_claims),
    do: Map.get(token_claims, "host")
end
