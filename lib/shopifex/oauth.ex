defmodule Shopifex.OAuth do
  @moduledoc """
  Shopify OAuth related functions.
  """

  @doc """
  Returns an url to redirect the user to the Shopify OAuth page.
  Shopify docs: <https://shopify.dev/docs/apps/build/authentication-authorization/access-tokens/authorization-code-grant#redirect-to-the-authorization-code-flow>
  """
  @spec oauth_redirect_url(String.t(), Keyword.t()) :: String.t()
  def oauth_redirect_url(shop_url, opts \\ []) do
    redirect_uri =
      Keyword.get(opts, :redirect_uri, Application.fetch_env!(:shopifex, :redirect_uri))

    query_params =
      URI.encode_query(%{
        client_id: Application.fetch_env!(:shopifex, :api_key),
        scope: Application.fetch_env!(:shopifex, :scopes),
        redirect_uri: redirect_uri,
        state: Keyword.get(opts, :state, "")
      })

    "https://#{shop_url}/admin/oauth/authorize"
    |> URI.new!()
    |> URI.append_query(query_params)
    |> URI.to_string()
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
