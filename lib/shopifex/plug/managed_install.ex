defmodule Shopifex.Plug.ManagedInstall do
  @moduledoc """
  Handles Shopify's managed app installation flow via token exchange, and keeps
  the embedded session's offline access token fresh.

  With managed installation (the default for new Shopify apps), Shopify sends an
  `id_token` JWT on every page load instead of going through the traditional
  OAuth authorization code exchange. This plug:

  1. Verifies the `id_token` with `Shopifex.SessionToken` (strict HS256).
  2. If the shop doesn't exist, exchanges the `id_token` for an **expiring**
     offline access token (RFC 8693) and persists the full token lifecycle
     (`access_token`, `token_expires_at`, `refresh_token`,
     `refresh_token_expires_at`).
  3. If the shop exists but its stored access token is within ~10 minutes of
     expiry (`token_expires_at`) or already expired — or its stored scopes lack
     any scope in `config :shopifex, :scopes` (a merchant approved a scope
     update) — it re-exchanges, which also persists Shopify's current grant.
  4. Otherwise it builds the session from the stored shop directly.

  New installs are persisted through the configurable
  `Shopifex.ManagedInstall.Callbacks` hooks (`insert_shop/1`, `after_install/1`,
  `after_exchange/2`), so apps can customise shop creation and side effects
  without re-implementing token exchange.

  ## Concurrency

  Concurrent embedded loads of the same shop (two tabs, a reload during a slow
  exchange, several app-load requests fanned out by the admin) are serialized
  per shop through `Shopifex.TokenRefreshLease` — the same lease
  `Shopifex.Auth.refresh/1` takes — so exactly one of them exchanges the
  `id_token`. The others poll the shop row and build their session from the
  pair the exchange persisted, without contacting Shopify; a first install
  inserts the row once. The `shopifex_token_refresh_leases` table is therefore
  required by this plug, not only by background refresh (see
  `docs/upgrading.md`). A load that cannot obtain or observe the lease within
  `config :shopifex, :token_refresh_wait_timeout_ms` (15s by default) logs a
  warning and exchanges without it. A re-exchange of an existing shop is
  written with the same locked compare `Shopifex.Auth.refresh/1` uses, so a
  pair that a refresh or another exchange persisted meanwhile is kept rather
  than overwritten. The lease is held until the exchange, its persistence, the
  webhook reconcile and the `Shopifex.ManagedInstall.Callbacks` hooks have
  run, so a hook that calls `Shopifex.Auth.refresh/1` for the same shop
  synchronously waits out the lease deadline and gets
  `{:error, :refresh_in_progress}`; run such work asynchronously.

  Webhooks are reconciled via `Shopifex.Shops.configure_webhooks/1` on first
  install **and on every re-exchange** (idempotent self-heal — see that function).
  Reconciliation issues one `webhookSubscriptions` query (plus a create per missing
  topic) per re-exchange, i.e. at most once per shop per ~50 min of activity; it
  does **not** run on the hot per-load path that builds the session from a fresh
  shop directly.

  If no recognised `id_token` is present, this plug is a no-op — the request
  falls through to the legacy OAuth flow (`Shopifex.Plug.ShopifySession`).

  > **No cookieless `auth_token` redirect bridge.** App Bridge supplies a fresh
  > `id_token` on every embedded load, so there is no need to bridge auth across a
  > cookieless redirect — this plug deliberately ships no `Phoenix.Token` redirect
  > branch. If your app issues its own signed-token redirect, keep that as a custom
  > plug clause; the library will not handle it.

  ## Usage

  Add this plug to your router pipeline **before** `Shopifex.Plug.ShopifySession`:

      pipeline :managed_install do
        plug Shopifex.Plug.ManagedInstall
      end

      scope "/auth" do
        pipe_through [:shopifex_browser, :managed_install, :shopify_session]
        get "/", MyAppWeb.AuthController, :auth
      end

  ## Configuration

      config :shopifex,
        api_key: "your_api_key",
        secret: "your_api_secret"

  Install-time side effects (profile fetch, analytics, snapshots) are
  app-specific and belong in your `AuthController` / shop-creation path, not in
  this plug.
  """

  require Logger

  alias Shopifex.TokenRefreshLease

  # Re-exchange the offline access token on the next id_token-bearing embedded
  # load once it is within this window of expiry (or already expired). Shopify's
  # expiring offline tokens have a ~1-hour TTL; a 10-minute buffer keeps the token
  # live through the page load. Background paths (schedulers, webhooks) refresh via
  # the refresh_token in `Shopifex.Auth` and don't depend on this plug.
  @refresh_before_expiry_seconds 10 * 60

  def init(opts), do: opts

  # Non-binary params (`?shop[a]=b`) fall through to the no-op clause: nothing
  # below could verify them, and interpolating a map into the log would raise.
  def call(%{params: %{"id_token" => id_token, "shop" => shop_url}} = conn, _opts)
      when is_binary(id_token) and is_binary(shop_url) do
    case Shopifex.SessionToken.verify(id_token, shop_url) do
      {:ok, _claims} ->
        load_or_exchange_shop(conn, id_token, shop_url)

      # Shopify session tokens live ~60s, so a stale embedded load (mobile
      # bfcache / back-forward, clock skew) routinely yields :expired. The
      # request still recovers — App Bridge supplies a fresh token on reload —
      # so this is expected, not an error. Log at :info; genuine anomalies (bad
      # signature/audience) stay :warning.
      {:error, :expired} ->
        Logger.info(
          "[Shopifex.ManagedInstall] Expired session token for #{shop_url}; falling through"
        )

        conn

      {:error, reason} ->
        Logger.warning(
          "[Shopifex.ManagedInstall] Invalid session token for #{shop_url}: #{inspect(reason)}"
        )

        conn
    end
  end

  def call(conn, _opts), do: conn

  defp load_or_exchange_shop(conn, id_token, shop_url) do
    case classify_shop(shop_url) do
      {:fresh, shop} ->
        build_session_from_shop(conn, shop)

      {:exchange, _reason, _shop} ->
        deadline = System.monotonic_time(:millisecond) + TokenRefreshLease.wait_timeout_ms()
        exchange_with_lease(conn, id_token, shop_url, deadline)
    end
  end

  # Reads the row and decides whether this load needs a token exchange. Cheap
  # enough to run again under the lease and on every poll while waiting, so a
  # process that lost the race to another exchange (or a background refresh)
  # observes the landed pair instead of issuing its own.
  defp classify_shop(shop_url) do
    case Shopifex.Shops.get_shop_by_url(shop_url) do
      nil ->
        {:exchange, :not_found, nil}

      shop ->
        cond do
          token_stale?(shop) -> {:exchange, :stale_token, shop}
          scopes_missing?(shop) -> {:exchange, :scopes_missing, shop}
          true -> {:fresh, shop}
        end
    end
  end

  # Exchanges are serialized per shop through the same lease `Shopifex.Auth`
  # takes for refresh-token grants: two embedded loads of a stale shop would
  # otherwise both exchange, and the pair that arrived last would be persisted
  # even if it was issued first (Shopify retires the older pair's refresh
  # token), while two first loads would both insert the shop. The lease is a
  # row in `shopifex_token_refresh_leases`; the Shopify request runs without
  # any lock on the shop row.
  defp exchange_with_lease(conn, id_token, shop_url, deadline) do
    case TokenRefreshLease.acquire(shop_url) do
      {:ok, owner} ->
        try do
          exchange_as_owner(conn, id_token, shop_url)
        after
          TokenRefreshLease.release(shop_url, owner)
        end

      :busy ->
        wait_for_exchange(conn, id_token, shop_url, deadline)
    end
  end

  defp exchange_as_owner(conn, id_token, shop_url) do
    case classify_shop(shop_url) do
      {:fresh, shop} ->
        Logger.info(
          "[Shopifex.ManagedInstall] Token for #{shop_url} was refreshed concurrently, skipping exchange"
        )

        build_session_from_shop(conn, shop)

      {:exchange, reason, shop} ->
        log_exchange_reason(reason, shop_url)
        exchange_token_and_upsert_shop(conn, id_token, shop_url, is_nil(shop), shop)
    end
  end

  # Another process holds the lease. Poll the row until it lands a usable
  # pair (then no HTTP call is made here at all) or the lease frees up. Past
  # the deadline the exchange runs uncoordinated, as it did before the lease
  # existed; the compare-and-persist in `persist_shop/3` still keeps a newer
  # pair from being overwritten.
  defp wait_for_exchange(conn, id_token, shop_url, deadline) do
    remaining_ms = deadline - System.monotonic_time(:millisecond)

    if remaining_ms <= 0 do
      Logger.warning(
        "[Shopifex.ManagedInstall] Token exchange lease for #{shop_url} still held past the wait deadline, exchanging without it"
      )

      case classify_shop(shop_url) do
        {:fresh, shop} ->
          build_session_from_shop(conn, shop)

        {:exchange, reason, shop} ->
          log_exchange_reason(reason, shop_url)
          exchange_token_and_upsert_shop(conn, id_token, shop_url, is_nil(shop), shop)
      end
    else
      poll_ms = min(TokenRefreshLease.poll_interval_ms(), remaining_ms)

      receive do
      after
        poll_ms -> :ok
      end

      case classify_shop(shop_url) do
        {:fresh, shop} ->
          Logger.info(
            "[Shopifex.ManagedInstall] Token for #{shop_url} was exchanged concurrently, skipping exchange"
          )

          build_session_from_shop(conn, shop)

        {:exchange, _reason, _shop} ->
          exchange_with_lease(conn, id_token, shop_url, deadline)
      end
    end
  end

  defp log_exchange_reason(:not_found, shop_url) do
    Logger.info("[Shopifex.ManagedInstall] Shop #{shop_url} not found, exchanging id_token")
  end

  defp log_exchange_reason(:stale_token, shop_url) do
    Logger.info("[Shopifex.ManagedInstall] Refreshing access_token for #{shop_url}")
  end

  defp log_exchange_reason(:scopes_missing, shop_url) do
    Logger.info(
      "[Shopifex.ManagedInstall] Stored scopes for #{shop_url} lack configured scopes, re-exchanging"
    )
  end

  # A merchant who approved newly configured scopes (a managed-install scope
  # update) still has the old scope list stored. With a fresh token the exchange
  # would otherwise be skipped and `EnsureScopes` would raise until the token
  # reached the refresh window — never, for a nil-expiry shop. Re-exchanging
  # returns Shopify's current grant, which `TokenResponse` persists. If the
  # grant is still short, `EnsureScopes` raises as before.
  defp scopes_missing?(shop) do
    required = Application.get_env(:shopifex, :scopes)
    granted = Shopifex.Shops.get_scope(shop)

    Shopifex.Scopes.missing(required, granted) != []
  end

  # Staleness is measured against `token_expires_at` — the token's actual lifetime
  # — NOT the row's `updated_at`, which any unrelated shop update would reset (an
  # expired token would then look fresh and skip re-exchange). A nil
  # `token_expires_at` is a non-expiring token (legacy / custom app); like
  # `Shopifex.Auth.ensure_fresh_token/1` it is treated as fresh — there is no
  # refresh_token to spend, so a 401 on it is terminal (`:no_refresh_token`).
  defp token_stale?(shop) do
    case Map.get(shop, :token_expires_at) do
      %DateTime{} = expires_at ->
        DateTime.diff(expires_at, DateTime.utc_now()) <= @refresh_before_expiry_seconds

      %NaiveDateTime{} = expires_at ->
        NaiveDateTime.diff(expires_at, NaiveDateTime.utc_now()) <= @refresh_before_expiry_seconds

      _ ->
        false
    end
  end

  defp exchange_token_and_upsert_shop(conn, id_token, shop_url, new?, fallback) do
    api_key = Application.fetch_env!(:shopifex, :api_key)
    api_secret = Application.fetch_env!(:shopifex, :secret)

    # `expiring=1` is required for public apps created on or after 2026-04-01:
    # https://shopify.dev/changelog/expiring-offline-access-tokens-required-for-public-apps-april-1-2026
    #
    # With `expiring=1` the response adds `expires_in` (typically 3600) and
    # `refresh_token` (+ `refresh_token_expires_in`, typically 90 days). We
    # persist all four so background paths can refresh without an id_token.
    body =
      URI.encode_query(%{
        "client_id" => api_key,
        "client_secret" => api_secret,
        "grant_type" => "urn:ietf:params:oauth:grant-type:token-exchange",
        "subject_token" => id_token,
        "subject_token_type" => "urn:ietf:params:oauth:token-type:id_token",
        "requested_token_type" => "urn:shopify:params:oauth:token-type:offline-access-token",
        "expiring" => "1"
      })

    req_opts =
      [
        body: body,
        headers: [{"content-type", "application/x-www-form-urlencoded"}]
      ] ++ Application.get_env(:shopifex, :req_options, [])

    case Req.post("https://#{shop_url}/admin/oauth/access_token", req_opts) do
      {:ok, %{status: 200, body: response_body}} when is_map(response_body) ->
        Logger.info("[Shopifex.ManagedInstall] Token exchange successful for #{shop_url}")

        attrs = Shopifex.TokenResponse.shop_attrs(shop_url, response_body)

        case persist_shop(new?, fallback, attrs) do
          {:ok, shop} ->
            build_session_from_shop(conn, shop)

          {:error, :shop_not_found} ->
            Logger.error(
              "[Shopifex.ManagedInstall] Shop #{shop_url} was deleted during token exchange"
            )

            fallback_session(conn, nil)
        end

      {:ok, %{status: status, body: body}} ->
        Logger.error(
          "[Shopifex.ManagedInstall] Token exchange failed for #{shop_url}: #{status} - #{inspect(body)}"
        )

        fallback_session(conn, fallback)

      {:error, error} ->
        Logger.error(
          "[Shopifex.ManagedInstall] Token exchange request failed for #{shop_url}: #{inspect(error)}"
        )

        fallback_session(conn, fallback)
    end
  end

  # First install: persist through the configurable managed-install callbacks so
  # apps can customise creation, then configure webhooks (first install only) and
  # run the first-install + every-exchange side-effect hooks. Only the lease
  # holder gets here for an absent row; a concurrent first load finds the
  # inserted row while polling, so no `on_conflict` upsert (which would need a
  # unique index custom schemas may lack) is required.
  defp persist_shop(_new? = true, _fallback, attrs) do
    callbacks = Shopifex.ManagedInstall.Callbacks.module()
    shop = callbacks.insert_shop(attrs)
    Shopifex.Shops.configure_webhooks(shop)
    callbacks.after_install(shop)
    callbacks.after_exchange(shop, true)
    {:ok, shop}
  end

  # Token refresh of an already-installed shop: update the token-lifecycle
  # fields, reconcile webhooks (idempotent self-heal — recovers from a failed
  # install registration or topics added to `:webhook_topics` later; runs at the
  # ≤50-minute re-exchange cadence, never on the hot per-load path), and run the
  # every-exchange hook (NOT the first-install hooks).
  #
  # The write is the same compare-and-persist `Shopifex.Auth.refresh/1` uses:
  # the row is locked and compared against `shop` as read before the HTTP
  # call. If a refresh or an uncoordinated exchange rotated the tokens in the
  # meantime, that pair is kept, the session is built from it, and the
  # webhook reconcile / `after_exchange` hook are skipped (the other writer ran
  # them for its exchange).
  #
  # `config :shopifex, :configure_webhooks_on_exchange?` (default `true`) gates
  # only this recurring reconcile — first install always registers. Set it to
  # `false` to skip the self-heal/query cost on every re-exchange (e.g. apps that
  # register once and never change topics). To disable Shopifex webhook
  # registration entirely (e.g. TOML-managed webhooks), set `:webhook_topics` to
  # `[]` instead.
  defp persist_shop(_new? = false, shop, attrs) do
    callbacks = Shopifex.ManagedInstall.Callbacks.module()

    case Shopifex.Auth.persist_token_pair(shop, attrs) do
      {:ok, persisted} ->
        shop = reload_for_session(persisted)

        if Application.get_env(:shopifex, :configure_webhooks_on_exchange?, true) do
          Shopifex.Shops.configure_webhooks(shop)
        end

        callbacks.after_exchange(shop, false)
        {:ok, shop}

      {:ok, :superseded, current} ->
        Logger.info(
          "[Shopifex.ManagedInstall] Token exchange for #{Shopifex.Shops.get_url(current)} superseded by a concurrent token write, keeping the stored pair"
        )

        {:ok, reload_for_session(current)}

      {:error, :shop_not_found} ->
        {:error, :shop_not_found}

      {:error, %Ecto.Changeset{} = changeset} ->
        raise Ecto.InvalidChangesetError, action: :update, changeset: changeset
    end
  end

  # The locked row comes straight from the schema, without the filters and
  # preloads `Shopifex.Shops.get_shop_by_url/1` applies; re-read it so the
  # session carries the same shape as a load that needed no exchange.
  defp reload_for_session(shop) do
    Shopifex.Shops.get_shop_by_url(Shopifex.Shops.get_url(shop)) || shop
  end

  defp build_session_from_shop(conn, shop) do
    host = conn.params["host"]
    locale = conn.params["locale"] || "en"
    Shopifex.Plug.build_session(conn, shop, host, locale)
  end

  # On exchange failure during a refresh, fall back to the existing shop's
  # session so the merchant can still load pages that don't hit Shopify APIs.
  # The stale token will 401 on actual API calls — but the next page load
  # retries the exchange.
  defp fallback_session(conn, nil), do: conn
  defp fallback_session(conn, shop), do: build_session_from_shop(conn, shop)
end
