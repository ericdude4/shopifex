defmodule Shopifex.Plug.ShopifyWebhook do
  import Plug.Conn

  def init(options) do
    # initialize options
    options
  end

  @doc """
  Ensures that the connection has a valid Shopify webhook HMAC token
  """
  def call(conn, _) do
    {header_hmac, our_hmac} =
      case conn.method do
        "GET" ->
          query_string =
            Regex.named_captures(~r/(?:hmac=[^&]*)&(?'query_string'.*)/, conn.query_string)[
              "query_string"
            ]

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

    if our_hmac == header_hmac do
      conn
    else
      conn
      |> send_resp(401, "invalid hmac signature")
      |> halt()
    end
  end
end
