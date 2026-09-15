defmodule ShopifexDummy.OAuthHTTPClient do
  @moduledoc """
  Test double for `Shopifex.OAuth.HTTPClient`. Responses are configured per test
  process with `expect/1`; every request is recorded and can be inspected with
  `requests/0`.

      ShopifexDummy.OAuthHTTPClient.expect({:ok, %{status_code: 200, body: ~s({"access_token": "x"})}})
      ShopifexDummy.OAuthHTTPClient.expect(fn url, body, headers -> ... end)
  """
  @behaviour Shopifex.OAuth.HTTPClient

  @responses_key {__MODULE__, :responses}
  @requests_key {__MODULE__, :requests}

  def expect(response_or_fun) do
    Process.put(@responses_key, Process.get(@responses_key, []) ++ [response_or_fun])
    :ok
  end

  def requests(), do: Process.get(@requests_key, []) |> Enum.reverse()

  def reset() do
    Process.delete(@responses_key)
    Process.delete(@requests_key)
    :ok
  end

  @impl true
  def post(url, body, headers) do
    Process.put(@requests_key, [
      %{url: url, body: Jason.decode!(body), headers: headers} | Process.get(@requests_key, [])
    ])

    case Process.get(@responses_key, []) do
      [] ->
        raise "#{inspect(__MODULE__)} received an unexpected request to #{url}"

      [response | rest] ->
        Process.put(@responses_key, rest)

        if is_function(response, 3) do
          response.(url, body, headers)
        else
          response
        end
    end
  end
end
