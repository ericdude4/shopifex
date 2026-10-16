defmodule Shopifex.API do
  @moduledoc """
  Shopify GraphQL Admin API transport.

  This is the library's single chokepoint for Admin API calls. Every request
  goes through `graphql/3`, which keeps expiring offline access tokens fresh:

  - **Proactive refresh** before the call (`Shopifex.Auth.fresh_token/1`): if
    the token will expire within ~5 minutes, refresh now so the request
    doesn't race the expiry.
  - **Reactive refresh** after a 401 (`Shopifex.Auth.refresh/1`): if Shopify
    rejects the token anyway (e.g. revoked early), refresh once and retry the
    request once.

  This is the strategy Shopify explicitly recommends:
  https://shopify.dev/changelog/offline-access-tokens-now-support-expiry-and-refresh

  ## Error propagation

  A refresh failure only short-circuits the request when it's *terminal*
  (`Shopifex.Auth.terminal_refresh_error?/1`) — a refresh token that's
  expired, missing, or rejected outright by Shopify. In that case `graphql/3`
  returns `{:error, {:token_refresh_failed, reason}}` without sending the
  GraphQL request at all:

  - Proactive terminal failure: no request is sent.
  - Reactive terminal failure (refresh after a 401): the same tuple is
    returned instead of the raw `{:error, {401, body}}`.

  A *transient* refresh failure (e.g. `:refresh_in_progress`, a 5xx from
  Shopify's token endpoint, or a transport error) doesn't block the request:
  it's sent with whatever token the shop currently has. The one exception is
  `:refresh_in_progress`, which also keeps the reactive 401 retry armed,
  since another process might finish the refresh before this request's
  token is checked. Any other transient failure disarms the reactive retry
  (it would just repeat the same failing attempt), so a 401 in that case
  returns the plain `{:error, {401, body}}`.

  ## What lives here vs. in your app

  This module ships only the *transport*. App-specific queries and mutations
  (products, inventory, metafields, …) belong in your application — call
  `Shopifex.API.graphql/3` from there. The library itself only uses this
  transport for webhook subscription and billing mutations.

  ## API version

  The Admin API version is configurable and defaults to `"2026-07"`:

      config :shopifex, :api_version, "2026-07"

  `api_version/0` is the single source of truth — webhook and billing code
  read it too.
  """

  alias Shopifex.Auth

  @default_api_version "2026-07"

  @doc """
  Run a GraphQL query/mutation against the shop's Admin API.

  Returns `{:ok, data}` on success, or `{:error, reason}` where `reason` is
  one of:

  - the GraphQL `errors` list (HTTP 200 with partial failure)
  - a `{status, body}` tuple for a non-200/401 response, or a 401 that
    survived the reactive refresh retry
  - a transport error (e.g. `%Req.TransportError{}`)
  - `{:token_refresh_failed, reason}` when a *terminal* token refresh
    failure stopped the request — see the moduledoc's "Error propagation"
    section
  """
  @spec graphql(struct(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def graphql(shop, query, variables \\ %{}) do
    case Auth.fresh_token(shop) do
      {:ok, fresh_shop} ->
        do_graphql(fresh_shop, query, variables, _allow_retry = true)

      # Someone else is refreshing; send with the current token and keep the
      # reactive 401 retry armed in case the refresh hasn't landed yet.
      {:error, :refresh_in_progress} ->
        do_graphql(shop, query, variables, _allow_retry = true)

      {:error, reason} ->
        if Auth.terminal_refresh_error?(reason) do
          {:error, {:token_refresh_failed, reason}}
        else
          # Transient failure other than refresh_in_progress (5xx from the
          # token endpoint, transport error, …): send with the current
          # token, but don't run the reactive 401 retry — it would just
          # repeat the refresh attempt that already failed.
          do_graphql(shop, query, variables, _allow_retry = false)
        end
    end
  end

  defp do_graphql(shop, query, variables, allow_retry?) do
    body = %{query: query}
    body = if variables != %{}, do: Map.put(body, :variables, variables), else: body

    req_opts =
      [
        json: body,
        headers: [{"x-shopify-access-token", shop.access_token}]
      ] ++ Application.get_env(:shopifex, :req_options, [])

    url = "https://#{Shopifex.Shops.get_url(shop)}/admin/api/#{api_version()}/graphql.json"

    case Req.post(url, req_opts) do
      # Errors take precedence even when "data" is present — Shopify returns
      # partial responses (`data: { foo: null }, errors: [...]`) when a single
      # field fails (e.g. missing scope). Without this we'd silently drop the
      # error and the caller would see a nil field with no clue why.
      {:ok, %{status: 200, body: %{"errors" => errors}}} ->
        {:error, errors}

      {:ok, %{status: 200, body: %{"data" => data}}} ->
        {:ok, data}

      # Reactive refresh: if Shopify says the token is bad, try to refresh once
      # and retry the request. Only refresh-retry once to avoid an infinite
      # loop if the refresh succeeds but the new token is still rejected.
      {:ok, %{status: 401}} = response when allow_retry? ->
        case Auth.refresh(shop) do
          {:ok, refreshed_shop} ->
            do_graphql(refreshed_shop, query, variables, _allow_retry = false)

          {:error, reason} ->
            if Auth.terminal_refresh_error?(reason) do
              {:error, {:token_refresh_failed, reason}}
            else
              unwrap_error(response)
            end
        end

      {:ok, response} ->
        unwrap_error({:ok, response})

      {:error, err} ->
        {:error, err}
    end
  end

  defp unwrap_error({:ok, %{status: status, body: body}}), do: {:error, {status, body}}

  @doc """
  The configured Shopify Admin API version. Defaults to `"#{@default_api_version}"`.
  """
  @spec api_version() :: String.t()
  def api_version, do: Application.get_env(:shopifex, :api_version, @default_api_version)
end
