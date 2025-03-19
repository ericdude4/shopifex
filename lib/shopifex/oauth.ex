defmodule Shopifex.OAuth do
  @moduledoc """
  Shopify OAuth related functions.
  """
  alias Plug.Conn

  @doc """
  Redirects the user to the Shopify OAuth page.
  Shopify docs: <https://shopify.dev/docs/apps/build/authentication-authorization/access-tokens/authorization-code-grant#redirect-to-the-authorization-code-flow>
  """
  @spec redirect_to_oauth(Conn.t(), String.t(), Keyword.t()) :: Conn.t()
  def redirect_to_oauth(%Conn{} = conn, shop_url, opts \\ []) do
    redirect_uri =
      Keyword.get(opts, :redirect_uri, Application.fetch_env!(:shopifex, :redirect_uri))

    query_params =
      URI.encode_query(%{
        client_id: Application.fetch_env!(:shopifex, :api_key),
        scope: Application.fetch_env!(:shopifex, :scopes),
        redirect_uri: redirect_uri,
        state: Keyword.get(opts, :state, "")
      })

    # The installation case and reinstallation case share the same URL, and query parameters,
    # except for the value of of the redirect_uri
    oauth_url =
      "https://#{shop_url}/admin/oauth/authorize"
      |> URI.new!()
      |> URI.append_query(query_params)
      |> URI.to_string()

    # Escape the iframe for embedded apps
    # https://shopify.dev/docs/apps/build/authentication-authorization/access-tokens/authorization-code-grant#check-for-and-escape-the-iframe-embedded-apps-only
    if Map.get(conn.params, "embedded") == "1" do
      conn
      |> Phoenix.Controller.put_layout(html: {ShopifexWeb.LayoutView, :app})
      |> Phoenix.Controller.put_view(ShopifexWeb.PageView)
      |> Phoenix.Controller.render("redirect.html", redirect_location: oauth_url, message: "")
      |> Plug.Conn.halt()
    else
      Phoenix.Controller.redirect(conn, external: oauth_url)
    end
  end

  @doc """
  Calls the Shopify OAuth endpoint to get the access token.
  Shopify docs: <https://shopify.dev/docs/apps/build/authentication-authorization/access-tokens/authorization-code-grant#step-4-get-an-access-token>
  """
  @spec post_access_token(String.t(), String.t()) ::
          {:ok, HTTPoison.Response.t()} | {:error, HTTPoison.Error.t()}
  def post_access_token(shop_domain, code) do
    headers = [
      "Content-Type": "application/json",
      Accept: "application/json"
    ]

    body = %{
      client_id: Application.fetch_env!(:shopifex, :api_key),
      client_secret: Application.fetch_env!(:shopifex, :secret),
      code: code
    }

    "https://#{shop_domain}/admin/oauth/access_token"
    |> URI.new!()
    |> URI.to_string()
    |> HTTPoison.post(Jason.encode!(body), headers)
  end
end
