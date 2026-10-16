defmodule Shopifex.Fixtures do
  @moduledoc """
  Fixtures for the tests
  """

  @doc """
  Creates a shop and builds a Shopifex session for it on the given conn,
  attaching a valid Shopify App Bridge session token (`Authorization: Bearer`)
  so `Shopifex.Plug.session_token/1` resolves and downstream re-auth (e.g. the
  payment-guard redirect) works in the Guardian-free model.
  """
  def shop_in_session(%{conn: conn}) do
    shop =
      Shopifex.Shops.create_shop(%{
        url: "shopifex.myshopify.com",
        scope: "orders",
        access_token: "asdf1234"
      })

    token = valid_session_token(shop.url)

    conn =
      conn
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      |> Shopifex.Plug.build_session(shop, "foo-host")

    {:ok, conn: conn, shop: shop, session_token: token}
  end

  @doc """
  Signs a valid Shopify App Bridge session token for `shop_url` using the test
  app secret/api_key.
  """
  def valid_session_token(shop_url) do
    secret = Application.fetch_env!(:shopifex, :secret)
    api_key = Application.fetch_env!(:shopifex, :api_key)
    now = System.system_time(:second)

    claims = %{
      "dest" => "https://#{shop_url}",
      "iss" => "https://#{shop_url}/admin",
      "aud" => api_key,
      "exp" => now + 60,
      "nbf" => now - 10,
      "iat" => now
    }

    jwk = JOSE.JWK.from_oct(secret)
    {_, token} = JOSE.JWT.sign(jwk, %{"alg" => "HS256"}, claims) |> JOSE.JWS.compact()
    token
  end
end
