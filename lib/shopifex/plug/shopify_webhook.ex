defmodule Shopifex.Plug.ShopifyWebhook do
  @moduledoc """
  Ensures that the connection has a valid Shopify webhook HMAC token and
  builds Shopifex session.
  """
  import Plug.Conn
  require Logger

  def init(options) do
    # initialize options
    options
  end

  def call(conn, _) do
    expected_hmac = build_hmac(conn)
    received_hmac = get_hmac(conn)

    if expected_hmac == received_hmac do
      shop =
        conn
        |> get_shop_domain()
        |> Shopifex.Shops.get_shop_by_url()

      if shop do
        host = Map.get(conn.params, "host")
        locale = Map.get(conn.params, "locale")
        Shopifex.Plug.build_session(conn, shop, host, locale)
      else
        conn
        |> send_resp(404, "no store found with url")
        |> halt()
      end
    else
      Logger.info("HMAC doesn't match " <> expected_hmac)

      conn
      |> send_resp(401, "invalid hmac signature")
      |> halt()
    end
  end

  defp build_hmac(%Plug.Conn{method: "GET"} = conn) do
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

    :crypto.hmac(
      :sha256,
      Application.fetch_env!(:shopifex, :secret),
      query_string
    )
    |> Base.encode16()
    |> String.downcase()
  end

  defp build_hmac(%Plug.Conn{method: "POST"} = conn) do
    :crypto.hmac(
      :sha256,
      Application.fetch_env!(:shopifex, :secret),
      conn.assigns[:raw_body]
    )
    |> Base.encode64()
  end

  defp get_hmac(%Plug.Conn{params: %{"hmac" => hmac}}), do: hmac

  defp get_hmac(%Plug.Conn{} = conn) do
    with [hmac_header] <- Plug.Conn.get_req_header(conn, "x-shopify-hmac-sha256") do
      hmac_header
    else
      _ -> nil
    end
  end

  defp get_shop_domain(%Plug.Conn{params: %{"myshopify_domain" => shop_url}}), do: shop_url
  defp get_shop_domain(%Plug.Conn{params: %{"shop" => shop_url}}), do: shop_url

  defp get_shop_domain(%Plug.Conn{} = conn) do
    with [shop_url] <- Plug.Conn.get_req_header(conn, "x-shopify-shop-domain") do
      shop_url
    else
      _ -> nil
    end
  end
end
