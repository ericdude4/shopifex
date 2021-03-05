defmodule Shopifex.Plug.ShopifySession do
  import Plug.Conn
  import Phoenix.Controller

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

  def initiate_new_session(conn = %{params: %{"hmac" => hmac}}) do
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
      |> do_initiate_new_session()
    else
      respond_invalid(conn)
    end
  end

  def initiate_new_session(conn), do: respond_invalid(conn)

  @doc """
  This function loads the session frame to get a temporary
  session token JWT from Shopify app bridge. See load-session.js
  """
  def do_initiate_new_session(conn = %{params: %{"shop" => shop_url}}) do
    redirect_after = build_redirect_after(conn)

    conn
    |> put_view(ShopifexWeb.AuthView)
    |> put_layout({ShopifexWeb.LayoutView, "app.html"})
    |> assign(:shop_url, shop_url)
    |> assign(:redirect_after, redirect_after)
    |> render("load-session.html")
    |> halt()
  end

  @shopify_validation_params [
    "hmac",
    "locale",
    "new_design_language",
    "session",
    "shop",
    "timestamp"
  ]
  defp build_redirect_after(conn) do
    # We won't need the Shopify validation params 'cause we are
    # validating w/ JWT for the rest of the session's lifetime
    params = Map.drop(conn.params, @shopify_validation_params)

    conn.request_path <> "?" <> URI.encode_query(params)
  end

  defp respond_invalid(conn) do
    conn
    |> put_view(ShopifexWeb.AuthView)
    |> put_layout({ShopifexWeb.LayoutView, "app.html"})
    |> render("select-store.html")
    |> halt()
  end
end
