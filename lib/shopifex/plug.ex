defmodule Shopifex.Plug do
  @moduledoc """
  An API for accessing the Shopify session data for the current request.
  """
  @type shop :: %{access_token: String.t(), scope: String.t(), url: String.t()}
  @type shopify_host :: String.t()

  @doc """
  Get current request shop resource for give `conn`.

  Available in all requests which have passed through a `:shopify_*` pipeline.

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
  passed through a `:shopify_*` pipeline.

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

  @doc """
  Places given shop into current session, making it accessible later on
  via `Shopifex.Plug.current_shop(conn)`
  """
  @spec put_shop_in_session(conn :: Plug.Conn.t(), shop :: shop()) :: Plug.Conn.t()
  def put_shop_in_session(conn, shop) do
    shopifex_private_data =
      conn.private
      |> Map.get(:shopifex, %{})
      |> Map.put(:shop, shop)

    Plug.Conn.put_private(conn, :shopifex, shopifex_private_data)
  end

  @spec build_hmac(conn :: Plug.Conn.t()) :: String.t()
  def build_hmac(%Plug.Conn{method: "GET"} = conn) do
    query_string =
      conn.query_params
      |> Enum.map(fn
        {"hmac", _value} ->
          nil

        {"ids", value} ->
          # This absolutely rediculous solution: https://community.shopify.com/c/Shopify-Apps/Hmac-Verification-for-Bulk-Actions/m-p/590611#M18504
          ids =
            Enum.map(value, fn id ->
              "\"#{id}\""
            end)
            |> Enum.join(", ")

          "ids=[#{ids}]"

        {key, value} ->
          "#{key}=#{value}"
      end)
      |> Enum.filter(&(!is_nil(&1)))
      |> Enum.join("&")

    :crypto.mac(
      :hmac,
      :sha256,
      Application.fetch_env!(:shopifex, :secret),
      query_string
    )
    |> Base.encode16()
    |> String.downcase()
  end

  def build_hmac(%Plug.Conn{method: "POST"} = conn) do
    :crypto.mac(
      :hmac,
      :sha256,
      Application.fetch_env!(:shopifex, :secret),
      conn.assigns[:raw_body]
    )
    |> Base.encode64()
    |> String.downcase()
  end

  @spec get_hmac(conn :: Plug.Conn.t()) :: String.t() | nil
  def get_hmac(%Plug.Conn{params: %{"hmac" => hmac}}), do: String.downcase(hmac)

  def get_hmac(%Plug.Conn{} = conn) do
    with [hmac_header] <- Plug.Conn.get_req_header(conn, "x-shopify-hmac-sha256") do
      String.downcase(hmac_header)
    else
      _ -> nil
    end
  end
end
