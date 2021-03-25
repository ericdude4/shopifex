defmodule Shopifex.Plug.ShopifyWebhook do
  import Plug.Conn
  require Logger

  def init(options) do
    # initialize options
    options
  end

  @doc """
  Ensures that the connection has a valid Shopify webhook HMAC token and puts the shop in conn.private
  """
  def call(conn, _) do
    {their_hmac, our_hmac} =
      case conn.method do
        "GET" ->
          query_string =
            conn.params
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

          {
            conn.params["hmac"],
            :crypto.hmac(
              :sha256,
              Application.fetch_env!(:shopifex, :secret),
              query_string
            )
            |> Base.encode16()
            |> String.downcase()
          }

        "POST" ->
          case Plug.Conn.get_req_header(conn, "x-shopify-hmac-sha256") do
            [header_hmac] ->
              our_hmac =
                :crypto.hmac(
                  :sha256,
                  Application.fetch_env!(:shopifex, :secret),
                  conn.assigns[:raw_body]
                )
                |> Base.encode64()

              {header_hmac, our_hmac}

            [] ->
              conn
              |> send_resp(401, "missing hmac signature")
              |> halt()
          end
      end

    if our_hmac == their_hmac do
      shop =
        case Plug.Conn.get_req_header(conn, "x-shopify-shop-domain") do
          [shop_url] ->
            shop_url

          _ ->
            conn.params["myshopify_domain"] || conn.query_params["shop"]
        end
        |> Shopifex.Shops.get_shop_by_url()

      Shopifex.Plug.ShopifySession.put_shop_in_session(conn, shop)
    else
      Logger.info("HMAC doesn't match " <> our_hmac)

      conn
      |> send_resp(401, "invalid hmac signature")
      |> halt()
    end
  end
end
