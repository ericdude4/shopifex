defmodule Shopifex.Plug.ValidateHmac do
  import Plug.Conn

  def init(options) do
    # initialize options
    options
  end

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
    else
      respond_invalid(conn)
    end
  end

  defp respond_invalid(conn) do
    conn
    |> resp(:forbidden, "No valid HMAC")
    |> send_resp()
    |> halt()
  end
end
