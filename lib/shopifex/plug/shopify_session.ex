defmodule Shopifex.Plug.ShopifySession do
  import Plug.Conn
  import Phoenix.Controller
  require Logger

  def init(options) do
    # initialize options
    options
  end

  def call(conn, _) do
    # Idempotent: guards against a bare `Plug.Test.conn/2` (no router/Plug.Parsers
    # in front) where `conn.query_params` is `%Plug.Conn.Unfetched{}` — reading it
    # below (directly, or via `hmac_matches?/2`'s query-string HMAC) would raise.
    conn = Plug.Conn.fetch_query_params(conn)

    # When `Shopifex.Plug.ManagedInstall` runs earlier in the pipeline it has
    # already verified the `id_token`, (re)exchanged the offline access token and
    # placed the shop in the session. Re-authenticating here would be redundant
    # and would fail for the managed-install request shape, so yield to it.
    if Shopifex.Plug.current_shop(conn) do
      conn
    else
      with :error <- authenticate_session_token(conn),
           :error <- authenticate_signed_redirect(conn) do
        initiate_new_session(conn)
      else
        {:ok, shop} ->
          Shopifex.Plug.build_session(conn, shop, get_host(conn), get_locale(conn))
      end
    end
  end

  # An app-issued redirect (see `Shopifex.Plug.PaymentGuard`) carries a
  # short-lived token bound to one destination path. It authenticates the shop
  # only when the request path equals the path signed into the token, so a
  # captured link cannot be replayed on another route.
  defp authenticate_signed_redirect(conn) do
    with token when is_binary(token) <- conn.query_params["redirect_token"],
         {:ok, shop_url} <- Shopifex.Plug.verify_redirect(token, conn.request_path),
         shop when not is_nil(shop) <- Shopifex.Shops.get_shop_by_url(shop_url) do
      {:ok, shop}
    else
      _ -> :error
    end
  end

  # Verify the Shopify App Bridge session token (`id_token`) and resolve the
  # shop it identifies. Replaces the Guardian token verification used in
  # Shopifex v2.
  defp authenticate_session_token(conn) do
    with token when is_binary(token) <- Shopifex.Plug.session_token(conn),
         {:ok, %{"dest" => "https://" <> shop_url}} <- Shopifex.SessionToken.verify(token),
         shop when not is_nil(shop) <- Shopifex.Shops.get_shop_by_url(shop_url) do
      {:ok, shop}
    else
      _ -> :error
    end
  end

  defp initiate_new_session(conn) do
    # Validate timestamp freshness if present, then constant-time compare
    # HMAC (and accept a rotated-out `:old_secret` if set).
    with :ok <- Shopifex.Plug.validate_timestamp(conn, require_timestamp: false),
         true <- Shopifex.Plug.hmac_matches?(conn, Shopifex.Plug.get_hmac(conn)) do
      conn
      |> do_new_session()
    else
      {:error, reason} ->
        Logger.info("Rejecting session request with invalid timestamp (#{reason})")
        respond_invalid(conn)

      false ->
        Logger.info("Rejecting session request with invalid HMAC")
        respond_invalid(conn)
    end
  end

  defp do_new_session(conn) do
    conn = Plug.Conn.fetch_query_params(conn)

    case conn.query_params["shop"] do
      shop_url when is_binary(shop_url) and shop_url != "" ->
        case Shopifex.Shops.get_shop_by_url(shop_url) do
          nil ->
            redirect_to_install(conn, shop_url)

          shop ->
            locale = get_locale(conn)
            host = get_host(conn)

            Shopifex.Plug.build_session(conn, shop, host, locale)
        end

      _ ->
        Logger.info("Rejecting session request without shop in query params")
        respond_invalid(conn)
    end
  end

  defp redirect_to_install(conn, shop_url) do
    Logger.info("Initiating shop installation for #{shop_url}")

    query =
      URI.encode_query(%{
        "client_id" => Application.fetch_env!(:shopifex, :api_key),
        "scope" => Application.fetch_env!(:shopifex, :scopes),
        "redirect_uri" => Application.fetch_env!(:shopifex, :redirect_uri)
      })

    conn
    |> redirect(external: "https://#{shop_url}/admin/oauth/authorize?#{query}")
    |> halt()
  end

  defp respond_invalid(%Plug.Conn{private: %{phoenix_format: "json"}} = conn) do
    conn
    |> put_status(:forbidden)
    |> put_view(ShopifexWeb.AuthJSON)
    |> render("403.json", message: "Unauthorized")
    |> halt()
  end

  defp respond_invalid(conn) do
    conn
    |> put_view(ShopifexWeb.AuthHTML)
    |> put_root_layout(html: false)
    |> put_layout(html: {ShopifexWeb.Layouts, :app})
    |> render("select_store.html")
    |> halt()
  end

  defp get_locale(%Plug.Conn{params: %{"locale" => locale}}), do: locale
  defp get_locale(_conn), do: Application.get_env(:shopifex, :default_locale, "en")

  defp get_host(%Plug.Conn{params: %{"host" => host}}), do: host
  defp get_host(_conn), do: nil
end
