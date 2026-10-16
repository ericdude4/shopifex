defmodule Shopifex.Plug.ManagedInstallTest.Callbacks do
  @moduledoc false
  use Shopifex.ManagedInstall.Callbacks

  @impl true
  def after_install(shop) do
    notify({:after_install, shop})
    :ok
  end

  @impl true
  def after_exchange(_shop, new?) do
    notify({:after_exchange, new?})
    :ok
  end

  defp notify(msg) do
    case Application.get_env(:shopifex, :managed_install_test_pid) do
      pid when is_pid(pid) -> send(pid, msg)
      _ -> :ok
    end
  end
end

defmodule Shopifex.Plug.ManagedInstallTest.OverrideCallbacks do
  @moduledoc false
  use Shopifex.ManagedInstall.Callbacks

  # Signals invocation AND stamps a marker onto the persisted record so the test
  # can prove the override's return value (not the default create_shop) is what
  # flows into the session / webhooks / after_install.
  @impl true
  def insert_shop(attrs) do
    case Application.get_env(:shopifex, :managed_install_test_pid) do
      pid when is_pid(pid) -> send(pid, {:insert_shop, attrs})
      _ -> :ok
    end

    Shopifex.Shops.create_shop(%{attrs | access_token: "OVERRIDDEN-" <> attrs.access_token})
  end
end

defmodule Shopifex.Plug.ManagedInstallTest do
  use Shopifex.DataCase, async: false

  import Ecto.Query
  import ExUnit.CaptureLog

  alias Shopifex.Shops
  alias Shopifex.Plug.ManagedInstall

  @secret "shpss_thisisafakesecret"
  @api_key "thisisafakeapikey"
  @shop "managed-install.myshopify.com"

  setup do
    Application.put_env(:shopifex, :managed_install_test_pid, self())

    Application.put_env(
      :shopifex,
      :managed_install_callbacks,
      Shopifex.Plug.ManagedInstallTest.Callbacks
    )

    on_exit(fn ->
      Application.delete_env(:shopifex, :managed_install_test_pid)
      Application.delete_env(:shopifex, :managed_install_callbacks)
    end)

    :ok
  end

  # --- helpers ---------------------------------------------------------------

  defp sign(claims) do
    jwk = JOSE.JWK.from_oct(@secret)
    {_, token} = JOSE.JWT.sign(jwk, %{"alg" => "HS256"}, claims) |> JOSE.JWS.compact()
    token
  end

  defp token(overrides \\ %{}) do
    now = System.system_time(:second)

    Map.merge(
      %{
        "dest" => "https://#{@shop}",
        "iss" => "https://#{@shop}/admin",
        "aud" => @api_key,
        "exp" => now + 60,
        "nbf" => now - 10,
        "iat" => now
      },
      overrides
    )
    |> sign()
  end

  defp conn_with(params), do: %Plug.Conn{params: params}

  defp token_exchange_response do
    %{
      "access_token" => "offline_access_token",
      "scope" => "read_orders",
      "expires_in" => 3600,
      "refresh_token" => "offline_refresh_token",
      "refresh_token_expires_in" => 7_776_000
    }
  end

  # One stub for the whole managed-install round trip: the RFC 8693 token
  # exchange (POST /admin/oauth/access_token) plus the GraphQL webhook
  # configuration. Notifies the test process so we can assert what ran.
  defp stub_shopify do
    parent = self()

    Req.Test.stub(Shopifex.ReqStub, fn conn ->
      if String.ends_with?(conn.request_path, "/admin/oauth/access_token") do
        send(parent, :token_exchanged)
        Req.Test.json(conn, token_exchange_response())
      else
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        query = Jason.decode!(body)["query"]

        if query =~ "webhookSubscriptionCreate" do
          send(parent, :webhook_created)

          Req.Test.json(conn, %{
            "data" => %{
              "webhookSubscriptionCreate" => %{
                "webhookSubscription" => %{"id" => "gid://shopify/WebhookSubscription/1"},
                "userErrors" => []
              }
            }
          })
        else
          Req.Test.json(conn, %{"data" => %{"webhookSubscriptions" => %{"edges" => []}}})
        end
      end
    end)
  end

  defp backdate_shop!(shop, seconds_ago) do
    old = NaiveDateTime.utc_now() |> NaiveDateTime.add(-seconds_ago, :second)

    Shops.repo().update_all(from(s in Shops.shop_schema(), where: s.id == ^shop.id),
      set: [updated_at: old]
    )
  end

  # A stub whose token exchange parks until the test sends `:continue` to the
  # requesting process, so a second load can be started while the first one is
  # "waiting on Shopify". Every exchange reports `{:token_exchange, pid}`, which
  # is how the race tests count HTTP calls. The stored scopes must satisfy
  # `config :shopifex, :scopes` ("orders") or the waiter would classify the
  # landed row as needing another exchange.
  defp stub_blocking_exchange(response) do
    parent = self()

    Req.Test.stub(Shopifex.ReqStub, fn conn ->
      if String.ends_with?(conn.request_path, "/admin/oauth/access_token") do
        send(parent, {:token_exchange, self()})

        receive do
          :continue -> Req.Test.json(conn, response)
        end
      else
        Req.Test.json(conn, %{"data" => %{"webhookSubscriptions" => %{"edges" => []}}})
      end
    end)
  end

  defp exchange_response(name) do
    %{
      "access_token" => "access_#{name}",
      "scope" => "orders",
      "expires_in" => 3600,
      "refresh_token" => "refresh_#{name}",
      "refresh_token_expires_in" => 7_776_000
    }
  end

  # Runs the plug in its own process, the way two request handlers would. The
  # task waits for `:run` so `Req.Test.allow/3` is in place before any HTTP
  # call; the shared sandbox (`async: false`) covers its database access.
  defp start_plug_task(params) do
    task =
      Task.async(fn ->
        receive do
          :run -> ManagedInstall.call(conn_with(params), [])
        end
      end)

    :ok = Req.Test.allow(Shopifex.ReqStub, self(), task.pid)
    send(task.pid, :run)
    task
  end

  defp stale_shop!(overrides \\ %{}) do
    Shops.create_shop(
      Map.merge(
        %{
          url: @shop,
          scope: "orders",
          access_token: "stale_token",
          token_expires_at:
            DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second),
          refresh_token: "stale_refresh"
        },
        overrides
      )
    )
  end

  defp put_wait_timeout!(ms) do
    previous = Application.fetch_env(:shopifex, :token_refresh_wait_timeout_ms)
    Application.put_env(:shopifex, :token_refresh_wait_timeout_ms, ms)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:shopifex, :token_refresh_wait_timeout_ms, value)
        :error -> Application.delete_env(:shopifex, :token_refresh_wait_timeout_ms)
      end
    end)
  end

  # --- new shop --------------------------------------------------------------

  test "new shop: exchanges id_token, persists the full token lifecycle, configures webhooks, invokes after_install, builds session" do
    stub_shopify()

    conn =
      ManagedInstall.call(conn_with(%{"id_token" => token(), "shop" => @shop, "host" => "h"}), [])

    assert_received :token_exchanged
    assert_received :webhook_created
    assert_received {:after_install, _shop}
    assert_received {:after_exchange, true}

    shop = Shops.get_shop_by_url(@shop)
    assert shop.access_token == "offline_access_token"
    assert shop.scope == "read_orders"
    assert %DateTime{} = shop.token_expires_at
    assert shop.refresh_token == "offline_refresh_token"
    assert %DateTime{} = shop.refresh_token_expires_at

    assert Shopifex.Plug.current_shop(conn).url == @shop
  end

  test "new shop: a token-exchange response that omits scope persists scope: nil (not \"\")" do
    parent = self()

    Req.Test.stub(Shopifex.ReqStub, fn conn ->
      if String.ends_with?(conn.request_path, "/admin/oauth/access_token") do
        send(parent, :token_exchanged)
        # Shopify may omit `scope` from the exchange response.
        Req.Test.json(conn, Map.delete(token_exchange_response(), "scope"))
      else
        Req.Test.json(conn, %{"data" => %{"webhookSubscriptions" => %{"edges" => []}}})
      end
    end)

    ManagedInstall.call(conn_with(%{"id_token" => token(), "shop" => @shop, "host" => "h"}), [])

    assert_received :token_exchanged

    shop = Shops.get_shop_by_url(@shop)
    assert shop.access_token == "offline_access_token"
    # The nullable scope field stays nil rather than being coerced to "".
    assert shop.scope == nil
  end

  test "new shop honors a custom insert_shop/1 override, whose return value flows into the session" do
    Application.put_env(
      :shopifex,
      :managed_install_callbacks,
      Shopifex.Plug.ManagedInstallTest.OverrideCallbacks
    )

    stub_shopify()

    conn = ManagedInstall.call(conn_with(%{"id_token" => token(), "shop" => @shop}), [])

    # The override ran (not the default create_shop)...
    assert_received {:insert_shop, _attrs}
    # ...and the record it returned is what was persisted and put in the session.
    assert Shopifex.Plug.current_shop(conn).access_token == "OVERRIDDEN-offline_access_token"
    assert Shops.get_shop_by_url(@shop).access_token == "OVERRIDDEN-offline_access_token"
  end

  # --- existing fresh shop ---------------------------------------------------

  test "existing fresh token: no re-exchange, even when an unrelated update aged updated_at" do
    # Stored scopes satisfy config :scopes ("orders"), so only token age matters.
    shop =
      Shops.create_shop(%{
        url: @shop,
        scope: "orders",
        access_token: "existing_token",
        token_expires_at:
          DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second),
        refresh_token: "existing_refresh"
      })

    # Age the row far past the old 50-minute `updated_at` threshold. Staleness is
    # now measured by token_expires_at, so this must NOT force a re-exchange.
    backdate_shop!(shop, 60 * 60)

    conn =
      ManagedInstall.call(conn_with(%{"id_token" => token(), "shop" => @shop, "host" => "h"}), [])

    refute_received :token_exchanged
    refute_received {:after_install, _}
    refute_received {:after_exchange, _}
    assert Shopifex.Plug.current_shop(conn).access_token == "existing_token"
  end

  # --- existing shop, scope update -------------------------------------------

  test "existing fresh token whose stored scopes lack a configured scope: re-exchanges and persists the new grant" do
    # Merchant approved a scope update; the stored row still has the old list.
    # A fresh token alone must not skip the exchange, or EnsureScopes would
    # raise until the token aged into the refresh window.
    Application.put_env(:shopifex, :scopes, "orders,read_products")
    Application.put_env(:shopifex, :configure_webhooks_on_exchange?, false)

    on_exit(fn ->
      Application.put_env(:shopifex, :scopes, "orders")
      Application.delete_env(:shopifex, :configure_webhooks_on_exchange?)
    end)

    Shops.create_shop(%{
      url: @shop,
      scope: "orders",
      access_token: "fresh_token",
      token_expires_at:
        DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second),
      refresh_token: "fresh_refresh"
    })

    parent = self()

    Req.Test.stub(Shopifex.ReqStub, fn conn ->
      send(parent, :token_exchanged)
      Req.Test.json(conn, %{token_exchange_response() | "scope" => "orders,read_products"})
    end)

    conn =
      ManagedInstall.call(conn_with(%{"id_token" => token(), "shop" => @shop, "host" => "h"}), [])

    assert_received :token_exchanged
    assert_received {:after_exchange, false}
    refute_received {:after_install, _}

    assert Shops.get_shop_by_url(@shop).scope == "orders,read_products"
    assert Shopifex.Plug.current_shop(conn).scope == "orders,read_products"
  end

  test "existing fresh token with a superset of the configured scopes: no re-exchange" do
    Shops.create_shop(%{
      url: @shop,
      scope: "orders,read_products",
      access_token: "existing_token",
      token_expires_at:
        DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second),
      refresh_token: "existing_refresh"
    })

    conn =
      ManagedInstall.call(conn_with(%{"id_token" => token(), "shop" => @shop, "host" => "h"}), [])

    refute_received :token_exchanged
    assert Shopifex.Plug.current_shop(conn).access_token == "existing_token"
  end

  # --- existing stale shop ---------------------------------------------------

  test "existing expired token: re-exchanges (despite a recent updated_at), refreshes lifecycle fields, reconciles webhooks, fires after_exchange, skips install hooks" do
    Shops.create_shop(%{
      url: @shop,
      scope: "read_orders",
      access_token: "stale_token",
      # Already expired — and updated_at is fresh (default on insert), so only the
      # token_expires_at check can trigger the re-exchange.
      token_expires_at:
        DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second),
      refresh_token: "stale_refresh"
    })

    stub_shopify()

    conn =
      ManagedInstall.call(conn_with(%{"id_token" => token(), "shop" => @shop, "host" => "h"}), [])

    assert_received :token_exchanged
    # A re-exchange reconciles webhooks (idempotent self-healing)...
    assert_received :webhook_created
    # ...runs the every-exchange hook with new?=false...
    assert_received {:after_exchange, false}
    # ...but must NOT re-run the first-install hook.
    refute_received {:after_install, _}

    refreshed = Shops.get_shop_by_url(@shop)
    assert refreshed.access_token == "offline_access_token"
    assert refreshed.refresh_token == "offline_refresh_token"
    assert Shopifex.Plug.current_shop(conn).access_token == "offline_access_token"
  end

  test "configure_webhooks_on_exchange?: false skips the reconcile on re-exchange (still re-exchanges the token)" do
    Application.put_env(:shopifex, :configure_webhooks_on_exchange?, false)
    on_exit(fn -> Application.delete_env(:shopifex, :configure_webhooks_on_exchange?) end)

    Shops.create_shop(%{
      url: @shop,
      scope: "read_orders",
      access_token: "stale_token",
      token_expires_at:
        DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second),
      refresh_token: "stale_refresh"
    })

    stub_shopify()

    conn =
      ManagedInstall.call(conn_with(%{"id_token" => token(), "shop" => @shop, "host" => "h"}), [])

    # The token is still re-exchanged and the every-exchange hook still runs...
    assert_received :token_exchanged
    assert_received {:after_exchange, false}
    # ...but the webhook reconcile is skipped.
    refute_received :webhook_created

    assert Shopifex.Plug.current_shop(conn).access_token == "offline_access_token"
  end

  # --- invalid / expired / missing tokens ------------------------------------

  test "invalid id_token: no-op (no exchange, no shop in session)" do
    conn = ManagedInstall.call(conn_with(%{"id_token" => "not-a-jwt", "shop" => @shop}), [])

    refute_received :token_exchanged
    assert Shopifex.Plug.current_shop(conn) == nil
    assert Shops.get_shop_by_url(@shop) == nil
  end

  test "expired id_token: no-op (falls through for App Bridge to retry with a fresh token)" do
    expired = token(%{"exp" => System.system_time(:second) - 120})

    conn = ManagedInstall.call(conn_with(%{"id_token" => expired, "shop" => @shop}), [])

    refute_received :token_exchanged
    assert Shopifex.Plug.current_shop(conn) == nil
  end

  test "non-binary shop or id_token: no-op instead of raising" do
    for params <- [
          %{"id_token" => "not-a-jwt", "shop" => %{"a" => "b"}},
          %{"id_token" => %{"a" => "b"}, "shop" => @shop},
          %{"id_token" => ["x"], "shop" => @shop}
        ] do
      conn = ManagedInstall.call(conn_with(params), [])

      refute_received :token_exchanged
      assert Shopifex.Plug.current_shop(conn) == nil
    end
  end

  test "no id_token: passes the conn through untouched" do
    conn = ManagedInstall.call(conn_with(%{"shop" => @shop}), [])

    refute_received :token_exchanged
    assert Shopifex.Plug.current_shop(conn) == nil
  end

  # --- concurrent loads (token-exchange lease) -------------------------------

  test "stale-token race: two concurrent loads exchange once and the waiter carries the persisted pair" do
    stale_shop!()
    stub_blocking_exchange(exchange_response("a"))
    params = %{"id_token" => token(), "shop" => @shop, "host" => "h"}

    # A reads the stale row, takes the lease and is now waiting on Shopify.
    a = start_plug_task(params)
    assert_receive {:token_exchange, a_request_pid}, 1_000

    # B reads the same stale row while A is in flight. It must wait on the
    # lease rather than issue its own exchange.
    b = start_plug_task(params)
    refute_receive {:token_exchange, _pid}, 300

    send(a_request_pid, :continue)
    a_conn = Task.await(a)
    b_conn = Task.await(b)

    # Exactly one exchange happened, and B built its session from A's pair.
    refute_received {:token_exchange, _pid}
    assert Shopifex.Plug.current_shop(a_conn).refresh_token == "refresh_a"
    assert Shopifex.Plug.current_shop(b_conn).access_token == "access_a"
    assert Shopifex.Plug.current_shop(b_conn).refresh_token == "refresh_a"

    stored = Shops.get_shop_by_url(@shop)
    assert stored.access_token == "access_a"
    assert stored.refresh_token == "refresh_a"

    assert_received {:after_exchange, false}
    refute_received {:after_exchange, _}
    refute_received {:after_install, _}
    assert Repo.aggregate("shopifex_token_refresh_leases", :count) == 0
  end

  test "first-install race: two concurrent first loads insert one row and run the install hooks once" do
    stub_blocking_exchange(exchange_response("install"))
    params = %{"id_token" => token(), "shop" => @shop, "host" => "h"}

    a = start_plug_task(params)
    assert_receive {:token_exchange, a_request_pid}, 1_000

    b = start_plug_task(params)
    refute_receive {:token_exchange, _pid}, 300

    send(a_request_pid, :continue)
    a_conn = Task.await(a)
    b_conn = Task.await(b)

    refute_received {:token_exchange, _pid}

    assert Repo.aggregate(from(s in Shops.shop_schema(), where: s.url == ^@shop), :count) == 1
    stored = Shops.get_shop_by_url(@shop)
    assert stored.access_token == "access_install"

    # The waiter's session is the row the lease holder inserted.
    assert Shopifex.Plug.current_shop(a_conn).id == stored.id
    assert Shopifex.Plug.current_shop(b_conn).id == stored.id
    assert Shopifex.Plug.current_shop(b_conn).refresh_token == "refresh_install"

    assert_received {:after_install, _shop}
    refute_received {:after_install, _}
    assert_received {:after_exchange, true}
    refute_received {:after_exchange, _}
  end

  test "superseded persist: a pair written while the exchange was in flight is kept, no hook runs" do
    shop = stale_shop!()
    parent = self()

    later =
      DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

    # Between this exchange's request and its response, "someone else" (a
    # refresh that won the row without the lease, e.g. after the lease TTL)
    # rotates the tokens. The exchange's own pair must not overwrite it.
    Req.Test.stub(Shopifex.ReqStub, fn conn ->
      if String.ends_with?(conn.request_path, "/admin/oauth/access_token") do
        send(parent, :token_exchanged)

        Shops.update_shop(shop, %{
          access_token: "refreshed_access",
          token_expires_at: later,
          refresh_token: "refreshed_refresh",
          refresh_token_expires_at: DateTime.add(later, 86_400, :second)
        })

        Req.Test.json(conn, exchange_response("exchange"))
      else
        send(parent, :webhook_reconciled)
        Req.Test.json(conn, %{"data" => %{"webhookSubscriptions" => %{"edges" => []}}})
      end
    end)

    conn =
      ManagedInstall.call(conn_with(%{"id_token" => token(), "shop" => @shop, "host" => "h"}), [])

    assert_received :token_exchanged

    stored = Shops.get_shop_by_url(@shop)
    assert stored.access_token == "refreshed_access"
    assert stored.refresh_token == "refreshed_refresh"

    # The session carries the row's pair, not the discarded exchange response...
    assert Shopifex.Plug.current_shop(conn).access_token == "refreshed_access"
    assert Shopifex.Plug.current_shop(conn).refresh_token == "refreshed_refresh"
    # ...and the every-exchange side effects belong to the writer that won.
    refute_received {:after_exchange, _}
    refute_received :webhook_reconciled
    assert Repo.aggregate("shopifex_token_refresh_leases", :count) == 0
  end

  test "deadline fallback: a lease held past the wait deadline logs a warning and the exchange still completes" do
    put_wait_timeout!(0)
    stale_shop!()

    Repo.insert_all("shopifex_token_refresh_leases", [
      %{
        shop_url: @shop,
        owner: "another-node",
        lease_expires_at: DateTime.add(DateTime.utc_now(), 60, :second)
      }
    ])

    stub_shopify()

    log =
      capture_log(fn ->
        conn =
          ManagedInstall.call(
            conn_with(%{"id_token" => token(), "shop" => @shop, "host" => "h"}),
            []
          )

        assert Shopifex.Plug.current_shop(conn).access_token == "offline_access_token"
      end)

    assert log =~ "still held past the wait deadline"
    assert_received :token_exchanged
    assert_received {:after_exchange, false}
    assert Shops.get_shop_by_url(@shop).refresh_token == "offline_refresh_token"

    # The foreign lease is left alone; only the owner may release it.
    assert Repo.aggregate("shopifex_token_refresh_leases", :count) == 1
  end

  test "a failed exchange releases the lease and falls back to the stored shop" do
    stale_shop!()
    parent = self()

    Req.Test.stub(Shopifex.ReqStub, fn conn ->
      send(parent, :token_exchanged)
      conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => "upstream"})
    end)

    _log =
      capture_log(fn ->
        conn =
          ManagedInstall.call(
            conn_with(%{"id_token" => token(), "shop" => @shop, "host" => "h"}),
            []
          )

        send(parent, {:conn, conn})
      end)

    assert_received {:conn, conn}
    assert_received :token_exchanged
    assert Shopifex.Plug.current_shop(conn).access_token == "stale_token"
    refute_received {:after_exchange, _}
    assert Repo.aggregate("shopifex_token_refresh_leases", :count) == 0
  end
end
