defmodule Shopifex.Plug.ShopifyWebhook do
  import Plug.Conn

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
            Regex.named_captures(~r/(?:hmac=[^&]*)&(?'query_string'.*)/, conn.query_string)[
              "query_string"
            ]
            |> URI.decode()
            |> (fn query_string ->
                  if Map.has_key?(conn.query_params, "ids") do
                    # This absolutely rediculous solution: https://community.shopify.com/c/Shopify-Apps/Hmac-Verification-for-Bulk-Actions/m-p/590611#M18504
                    query_string = Regex.replace(~r/ids\[\]\=[0-9]*\&/, query_string, "")
                    ids_section = Enum.join(conn.query_params["ids"], ~s(", "))

                    ~s(ids=["#{ids_section}"]&#{query_string})
                  else
                    query_string
                  end
                end).()

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
      shop = Shopifex.Shops.get_shop_by_url(conn.query_params["shop"])
      Shopifex.Plug.ShopifySession.put_shop_in_session(conn, shop)
    else
      conn
      |> send_resp(401, "invalid hmac signature")
      |> halt()
    end
  end
end
