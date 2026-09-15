defmodule Shopifex.OAuth.HTTPClient do
  @moduledoc """
  Behaviour for the HTTP client used by `Shopifex.OAuth` to talk to Shopify's
  token endpoint. Swap the implementation in tests with
  `config :shopifex, oauth_http_client: MyMock`.
  """

  @type response :: %{status_code: non_neg_integer(), body: binary()}

  @callback post(url :: String.t(), body :: binary(), headers :: [{String.t(), String.t()}]) ::
              {:ok, response()} | {:error, term()}
end

defmodule Shopifex.OAuth.HTTPClient.HTTPoison do
  @moduledoc false
  @behaviour Shopifex.OAuth.HTTPClient

  @impl true
  def post(url, body, headers) do
    case HTTPoison.post(url, body, headers) do
      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        {:ok, %{status_code: status_code, body: body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end
end
