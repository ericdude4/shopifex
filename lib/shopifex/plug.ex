defmodule Shopifex.Plug do
  @moduledoc """
  An API for accessing the Shopify session data for the current request.
  """
  @type shop :: %{access_token: String.t(), scope: String.t(), url: String.t()}
  @type shopify_host :: String.t()

  @doc """
  Get current request shop resource for give `conn`.

  Available in all requests which have passed through a `:shopifex_*` pipeline.

  ## Examples:

      iex> current_shop(conn)
      %MyApp.Shop{}

  """
  @spec current_shop(conn :: Plug.Conn.t()) :: shop()
  def current_shop(%Plug.Conn{private: %{shopifex: %{shop: shop}}}), do: shop
  def current_shop(_), do: nil

  @doc """
  Get host parameter provided in URL params when Shopify loaded
  your app in the Shopify admin portal.

  Useful when initializing app-bridge instance from SPA application.

  ## Examples:

      iex> current_shopify_host(conn)
      "host from URL search parameter"

  """
  @spec current_shopify_host(conn :: Plug.Conn.t()) :: shopify_host()
  def current_shopify_host(%Plug.Conn{private: %{shopifex: %{shopify_host: shopify_host}}}),
    do: shopify_host

  def current_shopify_host(_), do: nil

  @doc """
  Returns the token for the current session in a plug which has
  passed through the `:shopify_session` pipeline, or the
  `Shopifex.Plug.ShopifySession` plug.

  ## Example
      iex> session_token(conn)
      "header.payload.signature"
  """
  @spec session_token(conn :: Plug.Conn.t()) :: Guardian.Token.token() | nil
  def session_token(%Plug.Conn{} = conn), do: Guardian.Plug.current_token(conn)

  @doc """
  Build the Shopifex session. Used in various `:shopifex_*` pipelines.
  """
  @spec build_session(
          conn :: Plug.Conn.t(),
          shop :: shop(),
          shopify_host :: shopify_host(),
          locale :: Gettext.locale()
        ) :: Plug.Conn.t()
  def build_session(conn, shop, host, locale \\ "en") do
    Gettext.put_locale(locale || "en")

    {:ok, token, claims} =
      Shopifex.Guardian.encode_and_sign(shop, %{"loc" => locale, "host" => host})

    shopifex_private_data = %{
      shop: shop,
      shopify_host: host
    }

    conn
    |> Guardian.Plug.put_current_resource(shop)
    |> Guardian.Plug.put_current_claims(claims)
    |> Guardian.Plug.put_current_token(token)
    |> Plug.Conn.put_private(:shopifex, shopifex_private_data)
  end
end
