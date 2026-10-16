defmodule Shopifex.Auth do
  @moduledoc """
  Shopify access-token lifecycle for background / non-embedded paths.

  ## Why this module exists

  Shopify expiring offline access tokens have a 1-hour TTL. The embedded
  flow refreshes them via `Shopifex.Plug.ManagedInstall` (id_token →
  access_token exchange on every page load past a threshold). But
  background paths — schedulers, webhook handlers — don't have an
  id_token. They refresh independently using the stored `refresh_token`
  (90-day TTL, one-time use).

  This module is that refresh path. It is the background-equivalent of the
  embedded re-exchange, and `Shopifex.API.graphql/3` calls into it both
  proactively (before a request) and reactively (after a 401).

  ## Shopify's recommended strategy

  > "Proactively refresh tokens a few minutes before they expire, and
  > when you receive a 401 response."
  > -- https://shopify.dev/changelog/offline-access-tokens-now-support-expiry-and-refresh

  - **Proactive:** `ensure_fresh_token/1` checks `token_expires_at` and
    refreshes if it's within the safety window (5 minutes).
  - **Reactive:** `Shopifex.API.graphql/3` catches 401 responses and calls
    `refresh/1` once before retrying.

  ## Concurrency

  Refresh tokens are one-time use — using a refresh_token invalidates it
  immediately and the response includes a fresh refresh_token to use next
  time. If two callers refresh in parallel, the second one will get
  `invalid_grant` from Shopify and clobber the new refresh_token.

  To prevent that, `refresh/1` acquires a cross-node lease in the dedicated
  `shopifex_token_refresh_leases` table. The Shopify request runs without a
  transaction or lock on the consumer's shop row. After Shopify responds, a
  short transaction locks and re-checks the shop before persisting, so a
  concurrent managed-install exchange is never overwritten.

  ## Caveats

  - **Legacy installs have `refresh_token = nil`** — they were installed
    with the non-expiring offline token flow. For these shops,
    `ensure_fresh_token/1` returns the shop unchanged, `refresh/1` returns
    `{:error, :no_refresh_token}`, and the non-expiring access token keeps
    working for API calls. A 401 on such a token is terminal:
    `Shopifex.API.graphql/3` returns
    `{:error, {:token_refresh_failed, :no_refresh_token}}`, and the shop needs
    a new token exchange or a reinstall. Such a shop is **not** upgraded automatically: opening the
    embedded app does not re-exchange it, because `Shopifex.Plug.ManagedInstall`
    treats a `nil` `token_expires_at` as fresh (its `token_stale?` guard returns
    false for a nil expiry). The exception is a stored `scope` that lacks a
    configured scope, which does trigger a re-exchange. To move a legacy shop
    onto expiring tokens, back-fill it with `migrate_to_expiring_token/1` (see
    that function's docs) or have the merchant reinstall the app.

  - **If the refresh_token itself expires** (after 90 days of no refresh),
    Shopify returns 400 with `invalid_grant`. `refresh/1` returns
    `{:error, ...}`. The next embedded page load fixes it via fresh token
    exchange.

  ## Configuration

  Uses the existing Shopifex configuration:

      config :shopifex,
        api_key: "your_api_key",
        secret: "your_api_secret"

  Tests can inject Req options (e.g. a `Req.Test` plug) via:

      config :shopifex, :req_options, plug: {Req.Test, Shopifex.ReqStub}

  Refresh coordination can be tuned when necessary:

      config :shopifex,
        token_refresh_lease_ttl_ms: 120_000,
        token_refresh_wait_timeout_ms: 15_000,
        token_refresh_poll_interval_ms: 100

  ## References

  - About offline access tokens:
    https://shopify.dev/docs/apps/build/authentication-authorization/access-tokens/offline-access-tokens
  - Expiry & refresh changelog:
    https://shopify.dev/changelog/offline-access-tokens-now-support-expiry-and-refresh
  - Expiring offline access tokens required for public apps (Shopify changelog):
    https://shopify.dev/changelog/expiring-offline-access-tokens-required-for-public-apps-april-1-2026
  """

  require Logger
  import Ecto.Query

  alias Shopifex.TokenRefreshLease

  # Refresh proactively when the token is within this window of expiring.
  # Tuned to be longer than a typical Shopify API call so we don't race the
  # expiry while a request is in flight.
  @safety_window_seconds 5 * 60

  # Treat a refresh token this close to expiry as already spent. Shopify
  # rejects an expired refresh token with an opaque error, so checking locally
  # turns a doomed round-trip into an immediate, specific failure. Mirrors the
  # 60s allowance in ShopifyAPI::Auth::Session#refresh_token_expired?.
  @refresh_token_skew_seconds 60

  # Retry-related tuning for `refresh_retry/2`. See `request_refresh/1`.
  @refresh_retry_statuses [408, 429, 500, 502, 503, 504]
  @refresh_retry_transport_reasons [:timeout, :econnrefused, :closed]
  @refresh_retry_default_delay_ms 1_000
  @refresh_retry_max_delay_ms 5_000

  defp repo, do: Shopifex.Shops.repo()
  defp shop_schema, do: Shopifex.Shops.shop_schema()

  @doc """
  Returns `{:ok, shop}` with an access_token guaranteed fresh enough to make
  at least one Shopify API call against, or `{:error, reason}` if a needed
  refresh fails.

  Strategy:
  - Token expiry is unknown (`nil`) → `{:ok, shop}` as-is. The caller is
    responsible for invoking `refresh/1` reactively on 401. This covers
    legacy shops that pre-date the expiry columns.
  - Token expires within the safety window → refresh and return
    `refresh/1`'s result.
  - Otherwise → `{:ok, shop}` as-is.

  `reason` is whatever `refresh/1` returns; see its docs for the terminal
  vs. transient distinction (`terminal_refresh_error?/1`).
  """
  @spec fresh_token(struct()) :: {:ok, struct()} | {:error, term()}
  def fresh_token(shop) do
    cond do
      is_nil(Map.get(shop, :token_expires_at)) ->
        {:ok, shop}

      expires_within_safety_window?(shop) ->
        refresh(shop)

      true ->
        {:ok, shop}
    end
  end

  @doc """
  Same as `fresh_token/1`, but always returns the shop rather than an error
  tuple: on refresh failure it returns the (now-stale) input shop instead of
  propagating the error.

  This is the right default for background workers, where a transient
  refresh error shouldn't crash the caller. `Shopifex.API.graphql/3` reacts
  to a stale token via its 401 retry. Callers that need to distinguish
  success from failure (or terminal from transient errors) should call
  `fresh_token/1` directly.
  """
  @spec ensure_fresh_token(struct()) :: struct()
  def ensure_fresh_token(shop) do
    case fresh_token(shop) do
      {:ok, refreshed} -> refreshed
      {:error, _reason} -> shop
    end
  end

  @doc """
  Force-refresh the shop's access_token by exchanging its stored
  `refresh_token` for a new access + refresh token pair.

  Uses a cross-node database lease so concurrent callers don't both invalidate
  the same refresh token. The outbound Shopify request does not hold a lock on
  the shop row; only the final compare-and-persist step uses a short row lock.

  Returns `{:ok, refreshed_shop}` on success or `{:error, reason}` if Shopify
  rejects the refresh (most commonly `invalid_grant` when the refresh_token
  itself has expired) or the shop has no refresh_token.

  A caller that cannot acquire or observe completion of the lease before the
  configured wait deadline receives `{:error, :refresh_in_progress}`.

  A shop whose stored `refresh_token_expires_at` has passed (or is within a
  60s skew of passing) fails fast with `{:error, :refresh_token_expired}`
  without contacting Shopify. Recovery is the same as for a rejected refresh:
  the merchant opens the embedded app, and `Shopifex.Plug.ManagedInstall`
  re-exchanges the `id_token` for a fresh token pair.

  See `terminal_refresh_error?/1` for which `reason` values are worth
  giving up on vs. worth retrying later.
  """
  @spec refresh(struct()) :: {:ok, struct()} | {:error, term()}
  def refresh(shop) do
    deadline = System.monotonic_time(:millisecond) + TokenRefreshLease.wait_timeout_ms()
    refresh_with_lease(shop, deadline)
  end

  @doc """
  Exchange a legacy **non-expiring** offline access token for an expiring one
  plus a refresh token.

  This is the in-place way for a shop installed before expiring offline tokens
  existed to acquire a `refresh_token`. Until it runs (or the merchant
  reinstalls the app), `refresh/1` returns `{:error, :no_refresh_token}` for
  that shop. Re-opening the embedded app does **not** upgrade it:
  `Shopifex.Plug.ManagedInstall` treats a `nil` `token_expires_at` as fresh (its
  `token_stale?` guard returns false for a nil expiry) and re-exchanges only
  when the stored `scope` lacks a configured scope.

  > #### Irreversible {: .warning}
  >
  > Shopify destroys the non-expiring token in the same transaction that issues
  > the expiring pair. The call must never be retried — if the response is lost,
  > that shop has no usable token until a merchant reinstalls. The request pins
  > `retry: false` even when the host app configured retries globally.

  Expiring offline access tokens are required for public apps' GraphQL Admin API
  requests as of 2027-01-01.

  ## Back-filling an install base

  Idempotence lives in the *selection*, not the call — a shop that already has a
  `token_expires_at` has been migrated:

      import Ecto.Query

      MyApp.Repo.all(from s in MyApp.Shop, where: is_nil(s.token_expires_at))
      |> Enum.each(fn shop ->
        case Shopifex.Auth.migrate_to_expiring_token(shop) do
          {:ok, _migrated} -> :ok
          {:error, reason} -> MyApp.report_migration_failure(shop, reason)
        end
      end)

  Returns `{:ok, shop}`, or:

    * `{:error, :already_expiring}` — the shop already has a `token_expires_at`
    * `{:error, :no_access_token}` — nothing to exchange
    * `{:error, :shop_not_found}` — the row vanished between call and persist
    * `{:error, {:migrate_failed, status, body}}` — Shopify rejected the exchange
    * `{:error, {:migrate_request_failed, exception}}` — transport failure; the
      token may or may not have been cycled, so treat the shop as needing manual
      inspection rather than re-running this function
    * `{:error, {:persist_failed, changeset, attrs}}` — Shopify cycled the token
      but the database write failed. `attrs` carries the new token material so
      the caller can recover the shop; it is deliberately **not** logged.
  """
  @spec migrate_to_expiring_token(struct()) :: {:ok, struct()} | {:error, term()}
  def migrate_to_expiring_token(shop) do
    cond do
      not is_nil(Map.get(shop, :token_expires_at)) ->
        {:error, :already_expiring}

      is_nil(Map.get(shop, :access_token)) ->
        {:error, :no_access_token}

      true ->
        with {:ok, body} <- request_migration(shop) do
          persist_migrated_shop(shop, body)
        end
    end
  end

  @doc """
  Classifies a `refresh/1` / `fresh_token/1` error reason as terminal
  (retrying won't help without merchant action) or transient (worth retrying,
  e.g. with the shop's current token).

  Terminal: `:refresh_token_expired`, `:no_refresh_token`,
  `{:refresh_failed, 400}`, `{:refresh_failed, 401}`, `:shop_not_found`.

  Transient (returns `false`): `:refresh_in_progress`,
  `{:refresh_failed, 5xx}`, transport errors, and anything else unrecognized.

  `Shopifex.API.graphql/3` uses this to decide whether to send the request
  with a stale token or fail immediately.
  """
  @spec terminal_refresh_error?(term()) :: boolean()
  def terminal_refresh_error?(:refresh_token_expired), do: true
  def terminal_refresh_error?(:no_refresh_token), do: true
  def terminal_refresh_error?(:shop_not_found), do: true
  def terminal_refresh_error?({:refresh_failed, 400}), do: true
  def terminal_refresh_error?({:refresh_failed, 401}), do: true
  def terminal_refresh_error?(_reason), do: false

  defp refresh_with_lease(original_shop, deadline) do
    case reload_shop(original_shop) do
      nil ->
        {:error, :shop_not_found}

      current_shop ->
        cond do
          already_refreshed?(current_shop, original_shop) ->
            {:ok, current_shop}

          is_nil(Map.get(current_shop, :refresh_token)) ->
            {:error, :no_refresh_token}

          refresh_token_expired?(current_shop) ->
            {:error, :refresh_token_expired}

          true ->
            acquire_or_wait(current_shop, original_shop, deadline)
        end
    end
  end

  defp acquire_or_wait(current_shop, original_shop, deadline) do
    shop_url = Shopifex.Shops.get_url(current_shop)

    case TokenRefreshLease.acquire(shop_url) do
      {:ok, owner} ->
        try do
          refresh_as_owner(original_shop)
        after
          TokenRefreshLease.release(shop_url, owner)
        end

      :busy ->
        wait_for_refresh(original_shop, deadline)
    end
  end

  defp wait_for_refresh(original_shop, deadline) do
    remaining_ms = deadline - System.monotonic_time(:millisecond)

    if remaining_ms <= 0 do
      {:error, :refresh_in_progress}
    else
      poll_ms = min(TokenRefreshLease.poll_interval_ms(), remaining_ms)

      receive do
      after
        poll_ms -> refresh_with_lease(original_shop, deadline)
      end
    end
  end

  defp refresh_as_owner(original_shop) do
    case reload_shop(original_shop) do
      nil ->
        {:error, :shop_not_found}

      current_shop ->
        cond do
          already_refreshed?(current_shop, original_shop) ->
            {:ok, current_shop}

          is_nil(Map.get(current_shop, :refresh_token)) ->
            {:error, :no_refresh_token}

          refresh_token_expired?(current_shop) ->
            {:error, :refresh_token_expired}

          true ->
            with {:ok, response_body} <- request_refresh(current_shop) do
              handle_persisted_refresh(persist_refreshed_shop(current_shop, response_body))
            end
        end
    end
  end

  defp handle_persisted_refresh({:ok, refreshed_shop}) do
    Logger.info(
      "[Shopifex.Auth] Refresh token grant successful for #{Shopifex.Shops.get_url(refreshed_shop)}"
    )

    {:ok, refreshed_shop}
  end

  defp handle_persisted_refresh({:ok, :superseded, shop}) do
    Logger.info(
      "[Shopifex.Auth] Refresh token grant superseded by a concurrent token exchange for #{Shopifex.Shops.get_url(shop)}"
    )

    {:ok, shop}
  end

  defp handle_persisted_refresh({:error, _reason} = error), do: error

  defp request_refresh(shop) do
    api_key = Application.fetch_env!(:shopifex, :api_key)
    api_secret = Application.fetch_env!(:shopifex, :secret)
    url = Shopifex.Shops.get_url(shop)

    body =
      URI.encode_query(%{
        "client_id" => api_key,
        "client_secret" => api_secret,
        "grant_type" => "refresh_token",
        "refresh_token" => Map.get(shop, :refresh_token)
      })

    req_opts =
      [
        body: body,
        headers: [{"content-type", "application/x-www-form-urlencoded"}],
        # Shopify documents refreshes as resilient to ambiguous failures: a
        # request that times out, errors, or returns a transient 5xx should be
        # retried with the SAME refresh token, and the repeat returns the same
        # rotated credentials rather than issuing another pair.
        #
        # Req's built-in `retry: :transient` can't be used here: Req 0.5.17
        # parses the `Retry-After` header before consulting `:retry_delay`,
        # and `Req.Response.retry_delay_in_ms/1` only handles integer-second
        # values. Shopify documents a float (`Retry-After: 2.0`), which
        # raises `CaseClauseError` and would escape `refresh/1` into the
        # caller. `refresh_retry/2` below replaces it: same transient set
        # (408, 429, 500, 502, 503, 504, plus transport `:timeout` /
        # `:econnrefused` / `:closed`), but it parses `Retry-After` itself
        # (integer or float seconds, rounded up, capped at
        # `@refresh_retry_max_delay_ms`), falls back to a default delay for
        # an HTTP-date or unparseable value, and never returns `true` when
        # the header is present (that would hand the value back to Req's own
        # parser and hit the same crash).
        #
        # A terminal 400/401 is deliberately not in the transient set, so a
        # genuinely spent refresh token still fails immediately.
        #
        # Two retries (3 attempts total) rather than Req's default three:
        # these run while the refresh lease is held, and other callers are
        # waiting on `token_refresh_wait_timeout_ms` (15s by default) before
        # falling back to their stale token. Worst case: 3 attempts x (5s
        # connect + 10s receive) + 2 x 5s retry delay ~= 55s, comfortably
        # below the 120s lease TTL in `Shopifex.TokenRefreshLease`.
        retry: &refresh_retry/2,
        max_retries: 2,
        receive_timeout: 10_000,
        connect_options: [timeout: 5_000]
      ] ++ Application.get_env(:shopifex, :req_options, [])

    req =
      Req.new(req_opts)
      |> Req.Request.prepend_response_steps(
        refresh_sanitize_retry: &sanitize_refresh_retry_delay/1
      )

    case Req.post(req, url: "https://#{url}/admin/oauth/access_token") do
      {:ok, %{status: 200, body: response_body}} when is_map(response_body) ->
        {:ok, response_body}

      {:ok, %{status: status, body: response_body}} ->
        Logger.error(
          "[Shopifex.Auth] Refresh token grant failed for #{url}: #{status} - #{inspect(response_body)}"
        )

        {:error, {:refresh_failed, status}}

      {:error, error} ->
        Logger.error("[Shopifex.Auth] Refresh token request failed for #{url}: #{inspect(error)}")
        {:error, {:refresh_request_failed, error}}
    end
  end

  # Req raises when a `:retry` function returns `{:delay, ms}` while `:retry_delay`
  # is also set (deps/req/lib/req/steps.ex). Test config sets `retry_delay: 0`, so
  # without this step every Retry-After response would raise here in tests, and in
  # any host app that also configures `:retry_delay`.
  defp sanitize_refresh_retry_delay({request, %Req.Response{} = response}) do
    if refresh_retry_delay_ms(response) do
      {Req.Request.delete_option(request, :retry_delay), response}
    else
      {request, response}
    end
  end

  defp sanitize_refresh_retry_delay({request, other}), do: {request, other}

  # `retry: &refresh_retry/2` for the refresh request (see `request_refresh/1`
  # for why Req's own `:transient` retry can't be used).
  defp refresh_retry(_request, %Req.Response{status: status} = response)
       when status in @refresh_retry_statuses do
    case refresh_retry_delay_ms(response) do
      nil -> true
      ms -> {:delay, ms}
    end
  end

  defp refresh_retry(_request, %Req.TransportError{reason: reason})
       when reason in @refresh_retry_transport_reasons do
    true
  end

  defp refresh_retry(_request, _response_or_exception), do: false

  @doc false
  @spec refresh_retry_delay_ms(Req.Response.t()) :: non_neg_integer() | nil
  def refresh_retry_delay_ms(response) do
    case Req.Response.get_header(response, "retry-after") do
      [value] -> value |> parse_retry_after_seconds() |> to_capped_delay_ms()
      [] -> nil
    end
  end

  # Accepts integer or float seconds (Shopify documents a float, e.g. "2.0",
  # which Req 0.5.17's own parser can't handle). An HTTP-date or anything
  # else unparseable returns nil and falls back to the default delay.
  defp parse_retry_after_seconds(value) do
    case Float.parse(value) do
      {seconds, ""} when seconds >= 0 -> seconds
      _ -> nil
    end
  end

  defp to_capped_delay_ms(nil), do: @refresh_retry_default_delay_ms

  defp to_capped_delay_ms(seconds) do
    seconds |> Kernel.*(1000) |> ceil() |> min(@refresh_retry_max_delay_ms)
  end

  defp persist_refreshed_shop(shop, body) do
    persist_token_pair(shop, fn locked_shop ->
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      scope_field = Shopifex.Shops.get_scope_field()

      %{
        access_token: body["access_token"],
        token_expires_at: expires_at(now, body["expires_in"]),
        refresh_token: body["refresh_token"],
        refresh_token_expires_at: expires_at(now, body["refresh_token_expires_in"])
      }
      |> Map.put(scope_field, body["scope"] || Shopifex.Shops.get_scope(locked_shop))
    end)
  end

  @doc false
  @spec persist_token_pair(struct(), map() | (struct() -> map())) ::
          {:ok, struct()} | {:ok, :superseded, struct()} | {:error, term()}
  # Compare-and-persist for a token pair obtained from Shopify while no lock
  # was held: `snapshot` is the shop as read *before* the HTTP call, `attrs`
  # the fields to write (a map, or a function of the row as it is under the
  # lock). The row is locked `FOR UPDATE`; if its token state no longer
  # matches the snapshot, another writer (a managed-install exchange or a
  # refresh) rotated the tokens in the meantime and their pair is kept,
  # returning `{:ok, :superseded, current_row}` rather than clobbering it.
  # Shared by `refresh/1` and `Shopifex.Plug.ManagedInstall`.
  def persist_token_pair(snapshot, attrs) do
    schema = shop_schema()

    repo().transaction(fn ->
      locked_shop =
        repo().one(from(s in schema, where: s.id == ^snapshot.id, lock: "FOR UPDATE"))

      cond do
        is_nil(locked_shop) ->
          repo().rollback(:shop_not_found)

        # A concurrent writer already rotated the tokens (e.g. the merchant
        # opened the embedded app while this refresh was in flight). Their
        # pair wins; ours is discarded rather than clobbering it.
        token_state_changed?(locked_shop, snapshot) ->
          {:superseded, locked_shop}

        true ->
          attrs = if is_function(attrs, 1), do: attrs.(locked_shop), else: attrs

          case locked_shop |> schema.changeset(attrs) |> repo().update() do
            {:ok, persisted_shop} -> persisted_shop
            {:error, changeset} -> repo().rollback(changeset)
          end
      end
    end)
    |> case do
      {:ok, {:superseded, shop}} -> {:ok, :superseded, shop}
      {:ok, persisted_shop} -> {:ok, persisted_shop}
      {:error, reason} -> {:error, reason}
    end
  end

  defp reload_shop(shop) do
    case Map.get(shop, :id) do
      nil -> nil
      id -> repo().get(shop_schema(), id)
    end
  end

  defp already_refreshed?(current_shop, original_shop) do
    not expires_within_safety_window?(current_shop) and
      token_state_changed?(current_shop, original_shop)
  end

  defp token_state_changed?(current_shop, refreshed_snapshot) do
    Enum.any?(
      [:access_token, :token_expires_at, :refresh_token, :refresh_token_expires_at],
      &(Map.get(current_shop, &1) != Map.get(refreshed_snapshot, &1))
    )
  end

  defp expires_within_safety_window?(shop) do
    case Map.get(shop, :token_expires_at) do
      nil ->
        false

      %DateTime{} = expires_at ->
        DateTime.diff(expires_at, DateTime.utc_now(), :second) <= @safety_window_seconds

      %NaiveDateTime{} = expires_at ->
        NaiveDateTime.diff(expires_at, NaiveDateTime.utc_now(), :second) <=
          @safety_window_seconds
    end
  end

  # A `nil` expiry means the refresh token doesn't expire (or predates the
  # column), so it is never considered spent — same treatment legacy installs
  # get everywhere else in this module.
  defp refresh_token_expired?(shop) do
    case Map.get(shop, :refresh_token_expires_at) do
      nil ->
        false

      %DateTime{} = expires_at ->
        DateTime.diff(expires_at, DateTime.utc_now(), :second) <= @refresh_token_skew_seconds

      %NaiveDateTime{} = expires_at ->
        NaiveDateTime.diff(expires_at, NaiveDateTime.utc_now(), :second) <=
          @refresh_token_skew_seconds
    end
  end

  @offline_token_type "urn:shopify:params:oauth:token-type:offline-access-token"
  @token_exchange_grant "urn:ietf:params:oauth:grant-type:token-exchange"

  # Option order is the reverse of every other call site: config is appended
  # *before* `retry: false`, so a host app's global `retry:` cannot re-enable
  # retries on this unsafe, non-replayable exchange (later keys win).
  defp request_migration(shop) do
    url = Shopifex.Shops.get_url(shop)

    body =
      URI.encode_query(%{
        "client_id" => Application.fetch_env!(:shopifex, :api_key),
        "client_secret" => Application.fetch_env!(:shopifex, :secret),
        "grant_type" => @token_exchange_grant,
        "subject_token" => Map.get(shop, :access_token),
        "subject_token_type" => @offline_token_type,
        "requested_token_type" => @offline_token_type,
        "expiring" => "1"
      })

    req_opts =
      [
        body: body,
        headers: [{"content-type", "application/x-www-form-urlencoded"}]
      ] ++
        Application.get_env(:shopifex, :req_options, []) ++
        [retry: false]

    case Req.post("https://#{url}/admin/oauth/access_token", req_opts) do
      {:ok, %{status: 200, body: response_body}} when is_map(response_body) ->
        {:ok, response_body}

      {:ok, %{status: status, body: response_body}} ->
        Logger.error(
          "[Shopifex.Auth] Token migration failed for #{url}: #{status} - #{inspect(response_body)}"
        )

        {:error, {:migrate_failed, status, response_body}}

      {:error, exception} ->
        Logger.error(
          "[Shopifex.Auth] Token migration request failed for #{url}: #{inspect(exception)}"
        )

        {:error, {:migrate_request_failed, exception}}
    end
  end

  # Deliberately not `persist_refreshed_shop/2`: its compare-and-persist guard
  # treats a changed access_token as a concurrent exchange to yield to, but for
  # a migration a changed access_token is the expected result. Discarding it
  # would strand the shop, since Shopify has already destroyed the old token.
  defp persist_migrated_shop(shop, body) do
    schema = shop_schema()
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    scope_field = Shopifex.Shops.get_scope_field()

    attrs =
      %{
        access_token: body["access_token"],
        token_expires_at: expires_at(now, body["expires_in"]),
        refresh_token: body["refresh_token"],
        refresh_token_expires_at: expires_at(now, body["refresh_token_expires_in"])
      }
      |> Map.put(scope_field, body["scope"] || Shopifex.Shops.get_scope(shop))

    result =
      repo().transaction(fn ->
        case repo().one(from(s in schema, where: s.id == ^shop.id, lock: "FOR UPDATE")) do
          nil ->
            repo().rollback(:shop_not_found)

          locked_shop ->
            case locked_shop |> schema.changeset(attrs) |> repo().update() do
              {:ok, migrated} -> migrated
              {:error, changeset} -> repo().rollback({:persist_failed, changeset, attrs})
            end
        end
      end)

    case result do
      {:ok, migrated} ->
        Logger.info(
          "[Shopifex.Auth] Migrated #{Shopifex.Shops.get_url(migrated)} to an expiring offline token"
        )

        {:ok, migrated}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp expires_at(_now, nil), do: nil

  defp expires_at(now, seconds) when is_integer(seconds) do
    DateTime.add(now, seconds, :second)
  end
end
