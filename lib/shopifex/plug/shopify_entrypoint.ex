defmodule Shopifex.Plug.ShopifyEntrypoint do
  import Plug.Conn

  def init(options) do
    # initialize options
    options
  end

  @doc """
  Ensures that the connection has a valid Shopify HMAC token in the URL param, then sets
  `conn.private.valid_hmac` in the conn. You may want to handle this in your entry point
  by allowing the user without a valid HMAC to an install app page.
  """
  def call(conn = %{params: %{"hmac" => hmac}}, _) do
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
      |> put_private(:valid_hmac, true)
    else
      conn
      |> put_private(:valid_hmac, false)
    end
  end

  def call(conn, _) do
    conn
    |> put_private(:valid_hmac, false)
  end
end
