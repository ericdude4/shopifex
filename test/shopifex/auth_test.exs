defmodule Shopifex.AuthTest do
  use Shopifex.DataCase, async: false

  import ExUnit.CaptureLog

  alias Shopifex.{Auth, Shops}

  setup do
    {:ok, task_supervisor: start_supervised!(Task.Supervisor)}
  end

  defp token_response(opts \\ []) do
    %{
      "access_token" => Keyword.get(opts, :access_token, "new_access_token"),
      "scope" => Keyword.get(opts, :scope, "read_orders"),
      "expires_in" => Keyword.get(opts, :expires_in, 3600),
      "refresh_token" => Keyword.get(opts, :refresh_token, "new_refresh_token"),
      "refresh_token_expires_in" => Keyword.get(opts, :refresh_token_expires_in, 7_776_000)
    }
  end

  defp soon, do: DateTime.utc_now() |> DateTime.add(60, :second) |> DateTime.truncate(:second)
  defp later, do: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

  describe "ensure_fresh_token/1" do
    test "is a no-op when token_expires_at is nil (legacy / non-expiring install)" do
      shop =
        Shops.create_shop(%{
          url: "legacy.myshopify.com",
          scope: "read_orders",
          access_token: "legacy_token"
        })

      assert Auth.ensure_fresh_token(shop) == shop
    end

    test "returns the shop unchanged when the token is comfortably fresh" do
      shop =
        Shops.create_shop(%{
          url: "fresh.myshopify.com",
          scope: "read_orders",
          access_token: "tok",
          token_expires_at: later(),
          refresh_token: "rt"
        })

      assert Auth.ensure_fresh_token(shop).access_token == "tok"
    end

    test "proactively refreshes when the token is within the safety window" do
      Req.Test.stub(Shopifex.ReqStub, fn conn -> Req.Test.json(conn, token_response()) end)

      shop =
        Shops.create_shop(%{
          url: "soon.myshopify.com",
          scope: "read_orders",
          access_token: "old",
          token_expires_at: soon(),
          refresh_token: "rt"
        })

      refreshed = Auth.ensure_fresh_token(shop)
      assert refreshed.access_token == "new_access_token"
      assert refreshed.refresh_token == "new_refresh_token"
    end

    test "returns the shop unchanged when token_expires_at is a NaiveDateTime far in the future" do
      shop =
        Shops.create_shop(%{
          url: "naive-fresh.myshopify.com",
          scope: "read_orders",
          access_token: "tok",
          token_expires_at: later(),
          refresh_token: "rt"
        })

      naive_shop = %{
        shop
        | token_expires_at:
            NaiveDateTime.utc_now()
            |> NaiveDateTime.add(3600, :second)
            |> NaiveDateTime.truncate(:second)
      }

      assert Auth.ensure_fresh_token(naive_shop) == naive_shop
    end

    test "proactively refreshes when token_expires_at is a NaiveDateTime inside the safety window" do
      Req.Test.stub(Shopifex.ReqStub, fn conn -> Req.Test.json(conn, token_response()) end)

      shop =
        Shops.create_shop(%{
          url: "naive-soon.myshopify.com",
          scope: "read_orders",
          access_token: "old",
          token_expires_at: soon(),
          refresh_token: "rt"
        })

      naive_shop = %{
        shop
        | token_expires_at:
            NaiveDateTime.utc_now()
            |> NaiveDateTime.add(60, :second)
            |> NaiveDateTime.truncate(:second)
      }

      refreshed = Auth.ensure_fresh_token(naive_shop)
      assert refreshed.access_token == "new_access_token"
    end

    test "returns the stale shop when the refresh fails" do
      Req.Test.stub(Shopifex.ReqStub, fn conn ->
        conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "invalid_grant"})
      end)

      shop =
        Shops.create_shop(%{
          url: "ensure-fails.myshopify.com",
          scope: "read_orders",
          access_token: "old",
          token_expires_at: soon(),
          refresh_token: "rt"
        })

      log =
        capture_log(fn ->
          assert Auth.ensure_fresh_token(shop).access_token == "old"
        end)

      assert log =~ "Refresh token grant failed"
    end
  end

  describe "refresh/1" do
    test "persists all four token fields from the grant response" do
      Req.Test.stub(Shopifex.ReqStub, fn conn -> Req.Test.json(conn, token_response()) end)

      shop =
        Shops.create_shop(%{
          url: "r.myshopify.com",
          scope: "read_orders",
          access_token: "old",
          token_expires_at: soon(),
          refresh_token: "rt"
        })

      assert {:ok, refreshed} = Auth.refresh(shop)
      assert refreshed.access_token == "new_access_token"
      assert refreshed.refresh_token == "new_refresh_token"
      assert %DateTime{} = refreshed.token_expires_at
      assert %DateTime{} = refreshed.refresh_token_expires_at
    end

    test "tolerates a non-expiring grant response (nil expiry columns)" do
      Req.Test.stub(Shopifex.ReqStub, fn conn ->
        Req.Test.json(conn, %{"access_token" => "plain_token", "scope" => "read_orders"})
      end)

      shop =
        Shops.create_shop(%{
          url: "plain.myshopify.com",
          scope: "read_orders",
          access_token: "old",
          token_expires_at: soon(),
          refresh_token: "rt"
        })

      assert {:ok, refreshed} = Auth.refresh(shop)
      assert refreshed.access_token == "plain_token"
      assert is_nil(refreshed.token_expires_at)
      assert is_nil(refreshed.refresh_token)
    end

    test "returns {:error, :no_refresh_token} when the shop has no refresh_token" do
      shop =
        Shops.create_shop(%{
          url: "n.myshopify.com",
          scope: "read_orders",
          access_token: "old",
          token_expires_at: soon()
        })

      assert {:error, :no_refresh_token} = Auth.refresh(shop)
    end

    test "retries a transient 5xx with the same refresh token and succeeds" do
      attempts = :counters.new(1, [:atomics])

      Req.Test.stub(Shopifex.ReqStub, fn conn ->
        n = :counters.get(attempts, 1)
        :counters.add(attempts, 1, 1)

        if n == 0 do
          conn |> Plug.Conn.put_status(503) |> Req.Test.json(%{"error" => "unavailable"})
        else
          Req.Test.json(conn, token_response())
        end
      end)

      shop =
        Shops.create_shop(%{
          url: "transient-5xx.myshopify.com",
          scope: "read_orders",
          access_token: "old",
          token_expires_at: soon(),
          refresh_token: "rt"
        })

      capture_log(fn ->
        assert {:ok, refreshed} = Auth.refresh(shop)
        assert refreshed.access_token == "new_access_token"
      end)

      assert :counters.get(attempts, 1) == 2
    end

    test "retries a 429 with a float Retry-After header instead of crashing" do
      attempts = :counters.new(1, [:atomics])

      Req.Test.stub(Shopifex.ReqStub, fn conn ->
        n = :counters.get(attempts, 1)
        :counters.add(attempts, 1, 1)

        if n == 0 do
          conn
          |> Plug.Conn.put_resp_header("retry-after", "0.0")
          |> Plug.Conn.put_status(429)
          |> Req.Test.json(%{"error" => "rate_limited"})
        else
          Req.Test.json(conn, token_response())
        end
      end)

      shop =
        Shops.create_shop(%{
          url: "retry-after-float.myshopify.com",
          scope: "read_orders",
          access_token: "old",
          token_expires_at: soon(),
          refresh_token: "rt"
        })

      capture_log(fn ->
        assert {:ok, refreshed} = Auth.refresh(shop)
        assert refreshed.access_token == "new_access_token"
      end)

      assert :counters.get(attempts, 1) == 2
    end

    test "does not retry a terminal 400 — a spent refresh token fails fast" do
      attempts = :counters.new(1, [:atomics])

      Req.Test.stub(Shopifex.ReqStub, fn conn ->
        :counters.add(attempts, 1, 1)
        conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "invalid_grant"})
      end)

      shop =
        Shops.create_shop(%{
          url: "terminal-400.myshopify.com",
          scope: "read_orders",
          access_token: "old",
          token_expires_at: soon(),
          refresh_token: "spent"
        })

      log =
        capture_log(fn ->
          assert {:error, {:refresh_failed, 400}} = Auth.refresh(shop)
        end)

      assert log =~ "Refresh token grant failed"
      assert :counters.get(attempts, 1) == 1
    end

    test "gives up after the retry budget and releases the lease" do
      attempts = :counters.new(1, [:atomics])

      Req.Test.stub(Shopifex.ReqStub, fn conn ->
        :counters.add(attempts, 1, 1)
        conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => "boom"})
      end)

      shop =
        Shops.create_shop(%{
          url: "always-5xx.myshopify.com",
          scope: "read_orders",
          access_token: "old",
          token_expires_at: soon(),
          refresh_token: "rt"
        })

      capture_log(fn ->
        assert {:error, {:refresh_failed, 500}} = Auth.refresh(shop)
      end)

      # 1 initial attempt + max_retries: 2
      assert :counters.get(attempts, 1) == 3
      assert Repo.aggregate("shopifex_token_refresh_leases", :count) == 0
    end

    test "returns {:error, {:refresh_failed, status}} when Shopify rejects the grant" do
      Req.Test.stub(Shopifex.ReqStub, fn conn ->
        conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "invalid_grant"})
      end)

      shop =
        Shops.create_shop(%{
          url: "bad.myshopify.com",
          scope: "read_orders",
          access_token: "old",
          token_expires_at: soon(),
          refresh_token: "expired_rt"
        })

      capture_log(fn ->
        assert {:error, {:refresh_failed, 400}} = Auth.refresh(shop)
      end)
    end

    test "returns {:error, :shop_not_found} for a plain map without an :id" do
      shop = %{url: "mapless.myshopify.com", refresh_token: "rt"}

      assert {:error, :shop_not_found} = Auth.refresh(shop)
    end

    test "returns {:error, :shop_not_found} when the shop is deleted mid-flight" do
      shop =
        Shops.create_shop(%{
          url: "deleted-mid-flight.myshopify.com",
          scope: "read_orders",
          access_token: "old",
          token_expires_at: soon(),
          refresh_token: "rt"
        })

      Shops.delete_shop(shop)

      assert {:error, :shop_not_found} = Auth.refresh(shop)
    end

    test "second caller observes the first caller's fresh token without re-hitting Shopify" do
      # Pre-write a fresh token as if a concurrent caller already refreshed,
      # then call refresh/1 with a stale in-memory copy. The initial reload
      # should short-circuit and return the fresh row.
      shop =
        Shops.create_shop(%{
          url: "concurrent.myshopify.com",
          scope: "read_orders",
          access_token: "stale",
          token_expires_at: soon(),
          refresh_token: "rt"
        })

      _ =
        Shops.update_shop(shop, %{
          access_token: "stale",
          token_expires_at: later(),
          refresh_token: "already_rotated"
        })

      # No Req.Test stub registered → if this tried to hit Shopify it would raise.
      assert {:ok, observed} = Auth.refresh(shop)
      assert observed.access_token == "stale"
      assert observed.refresh_token == "already_rotated"
    end

    test "serializes concurrent refreshes without reusing a one-time token", %{
      task_supervisor: task_supervisor
    } do
      test_pid = self()

      Req.Test.stub(Shopifex.ReqStub, fn conn ->
        send(test_pid, {:refresh_request, self()})

        receive do
          :release_refresh -> Req.Test.json(conn, token_response())
        end
      end)

      shop =
        Shops.create_shop(%{
          url: "serialized.myshopify.com",
          scope: "read_orders",
          access_token: "old",
          token_expires_at: soon(),
          refresh_token: "single_use_rt"
        })

      first = start_refresh_task(task_supervisor, shop)
      assert_receive {:refresh_request, request_pid}, 1_000

      second = start_refresh_task(task_supervisor, shop)
      refute_receive {:refresh_request, _pid}, 100

      send(request_pid, :release_refresh)

      assert {:ok, first_shop} = task_result(first)
      assert {:ok, second_shop} = task_result(second)
      assert first_shop.access_token == "new_access_token"
      assert second_shop.access_token == "new_access_token"
      assert first_shop.refresh_token == "new_refresh_token"
      assert second_shop.refresh_token == "new_refresh_token"
      refute_receive {:refresh_request, _pid}, 100
    end

    test "preserves a concurrent unrelated shop update made while the refresh awaits Shopify", %{
      task_supervisor: task_supervisor
    } do
      # Under the sandbox every process shares one connection, so this cannot
      # observe row locks; it proves the persist step merges a concurrent
      # write instead of clobbering it. The lock itself is tested below.
      test_pid = self()

      Req.Test.stub(Shopifex.ReqStub, fn conn ->
        send(test_pid, {:refresh_request, self()})

        receive do
          :release_refresh -> Req.Test.json(conn, Map.delete(token_response(), "scope"))
        end
      end)

      shop =
        Shops.create_shop(%{
          url: "unlocked.myshopify.com",
          scope: "read_orders",
          access_token: "old",
          token_expires_at: soon(),
          refresh_token: "rt"
        })

      refresh_task = start_refresh_task(task_supervisor, shop)
      assert_receive {:refresh_request, request_pid}, 1_000

      update_task =
        start_task(task_supervisor, fn ->
          Shops.update_shop(shop, %{scope: "write_orders"})
        end)

      updated = task_result(update_task)
      assert updated.scope == "write_orders"

      send(request_pid, :release_refresh)

      assert {:ok, refreshed} = task_result(refresh_task)
      assert refreshed.scope == "write_orders"
      assert refreshed.access_token == "new_access_token"
    end

    test "holds no shop-row lock while waiting for Shopify (independent DB connections)", %{
      task_supervisor: task_supervisor
    } do
      # The sandbox shares one connection across processes, where a row lock
      # can never block, so this test steps outside it: each participant checks
      # out its own pooled connection, rows are committed for real, and on_exit
      # deletes them.
      alias Ecto.Adapters.SQL.Sandbox
      url = "unboxed-lock.myshopify.com"
      test_pid = self()

      Req.Test.stub(Shopifex.ReqStub, fn conn ->
        send(test_pid, {:refresh_request, self()})

        receive do
          :release_refresh -> Req.Test.json(conn, token_response())
        end
      end)

      shop =
        Sandbox.unboxed_run(Repo, fn ->
          Shops.create_shop(%{
            url: url,
            scope: "read_orders",
            access_token: "old",
            token_expires_at: soon(),
            refresh_token: "rt"
          })
        end)

      on_exit(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.delete_all(from(s in ShopifexDummy.Shop, where: s.url == ^url))
          Repo.delete_all(from(l in "shopifex_token_refresh_leases", where: l.shop_url == ^url))
        end)
      end)

      refresh_task =
        start_task(
          task_supervisor,
          fn -> Sandbox.unboxed_run(Repo, fn -> Auth.refresh(shop) end) end,
          start?: false
        )

      :ok = Req.Test.allow(Shopifex.ReqStub, self(), refresh_task.pid)
      send(refresh_task.pid, :run)

      assert_receive {:refresh_request, request_pid}, 1_000

      # While the refresh is parked inside the HTTP call, a second, independent
      # connection must be able to lock the row at once. NOWAIT turns a held
      # lock into an immediate error instead of a hang.
      lock_result =
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            Repo.one(
              from(s in ShopifexDummy.Shop, where: s.id == ^shop.id, lock: "FOR UPDATE NOWAIT")
            )
          end)
        end)

      assert {:ok, %ShopifexDummy.Shop{}} = lock_result

      send(request_pid, :release_refresh)

      assert {:ok, refreshed} = task_result(refresh_task)
      assert refreshed.access_token == "new_access_token"
    end

    test "does not overwrite a newer managed-install token pair", %{
      task_supervisor: task_supervisor
    } do
      prev_level = Logger.level()
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: prev_level) end)
      test_pid = self()

      Req.Test.stub(Shopifex.ReqStub, fn conn ->
        send(test_pid, {:refresh_request, self()})

        receive do
          :release_refresh -> Req.Test.json(conn, token_response())
        end
      end)

      shop =
        Shops.create_shop(%{
          url: "managed-wins.myshopify.com",
          scope: "read_orders",
          access_token: "old",
          token_expires_at: soon(),
          refresh_token: "old_rt"
        })

      refresh_task = start_refresh_task(task_supervisor, shop)
      assert_receive {:refresh_request, request_pid}, 1_000

      managed_expires_at = later()

      managed_shop =
        Shops.update_shop(shop, %{
          access_token: "managed_access",
          token_expires_at: managed_expires_at,
          refresh_token: "managed_refresh",
          refresh_token_expires_at: DateTime.add(managed_expires_at, 86_400, :second)
        })

      prev_level = Logger.level()
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: prev_level) end)

      log =
        capture_log(fn ->
          send(request_pid, :release_refresh)
          assert {:ok, observed} = task_result(refresh_task)
          assert observed.access_token == "managed_access"
          assert observed.refresh_token == "managed_refresh"
        end)

      assert log =~ "superseded by a concurrent token exchange"

      persisted = Repo.get!(ShopifexDummy.Shop, managed_shop.id)
      assert persisted.access_token == "managed_access"
      assert persisted.refresh_token == "managed_refresh"
    end

    test "releases its lease after Shopify rejects the refresh" do
      Req.Test.stub(Shopifex.ReqStub, fn conn ->
        conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "invalid_grant"})
      end)

      shop =
        Shops.create_shop(%{
          url: "retry-after-failure.myshopify.com",
          scope: "read_orders",
          access_token: "old",
          token_expires_at: soon(),
          refresh_token: "rt"
        })

      capture_log(fn ->
        assert {:error, {:refresh_failed, 400}} = Auth.refresh(shop)
      end)

      assert Repo.aggregate("shopifex_token_refresh_leases", :count) == 0

      Req.Test.stub(Shopifex.ReqStub, fn conn -> Req.Test.json(conn, token_response()) end)

      assert {:ok, refreshed} = Auth.refresh(shop)
      assert refreshed.access_token == "new_access_token"
    end

    test "returns refresh_in_progress when the lease wait deadline is exhausted" do
      previous = Application.fetch_env(:shopifex, :token_refresh_wait_timeout_ms)
      Application.put_env(:shopifex, :token_refresh_wait_timeout_ms, 0)

      on_exit(fn ->
        case previous do
          {:ok, value} -> Application.put_env(:shopifex, :token_refresh_wait_timeout_ms, value)
          :error -> Application.delete_env(:shopifex, :token_refresh_wait_timeout_ms)
        end
      end)

      shop =
        Shops.create_shop(%{
          url: "busy.myshopify.com",
          scope: "read_orders",
          access_token: "old",
          token_expires_at: soon(),
          refresh_token: "rt"
        })

      Repo.insert_all("shopifex_token_refresh_leases", [
        %{
          shop_url: shop.url,
          owner: "another-node",
          lease_expires_at: DateTime.add(DateTime.utc_now(), 60, :second)
        }
      ])

      assert {:error, :refresh_in_progress} = Auth.refresh(shop)
    end
  end

  defp start_refresh_task(task_supervisor, shop) do
    task = start_task(task_supervisor, fn -> Auth.refresh(shop) end, start?: false)
    :ok = Req.Test.allow(Shopifex.ReqStub, self(), task.pid)
    send(task.pid, :run)
    task
  end

  describe "migrate_to_expiring_token/1" do
    test "exchanges a non-expiring token and persists all four columns" do
      Req.Test.stub(Shopifex.ReqStub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)

        # The distinguishing feature of this grant: the subject token is the
        # access token itself, typed as an offline access token (not an id_token).
        assert params["grant_type"] == "urn:ietf:params:oauth:grant-type:token-exchange"
        assert params["subject_token"] == "legacy_non_expiring"

        assert params["subject_token_type"] ==
                 "urn:shopify:params:oauth:token-type:offline-access-token"

        assert params["requested_token_type"] ==
                 "urn:shopify:params:oauth:token-type:offline-access-token"

        assert params["expiring"] == "1"

        Req.Test.json(conn, token_response())
      end)

      shop =
        Shops.create_shop(%{
          url: "legacy-mig.myshopify.com",
          scope: "read_orders",
          access_token: "legacy_non_expiring",
          token_expires_at: nil,
          refresh_token: nil
        })

      assert {:ok, migrated} = Auth.migrate_to_expiring_token(shop)
      assert migrated.access_token == "new_access_token"
      assert migrated.refresh_token == "new_refresh_token"
      assert migrated.token_expires_at
      assert migrated.refresh_token_expires_at
    end

    test "refuses a shop that already has an expiring token" do
      # No stub: reaching the network would raise and fail the test.
      shop =
        Shops.create_shop(%{
          url: "already-mig.myshopify.com",
          scope: "read_orders",
          access_token: "tok",
          token_expires_at: later()
        })

      assert {:error, :already_expiring} = Auth.migrate_to_expiring_token(shop)
    end

    test "refuses a shop with no access_token" do
      # A bare struct — the changeset requires access_token, and this branch
      # returns before any DB or network access anyway.
      shop = %ShopifexDummy.Shop{
        url: "no-token-mig.myshopify.com",
        scope: "read_orders",
        access_token: nil,
        token_expires_at: nil
      }

      assert {:error, :no_access_token} = Auth.migrate_to_expiring_token(shop)
    end

    test "surfaces a Shopify rejection without touching the shop row" do
      Req.Test.stub(Shopifex.ReqStub, fn conn ->
        conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "invalid_subject_token"})
      end)

      shop =
        Shops.create_shop(%{
          url: "reject-mig.myshopify.com",
          scope: "read_orders",
          access_token: "legacy",
          token_expires_at: nil
        })

      capture_log(fn ->
        assert {:error, {:migrate_failed, 400, _body}} = Auth.migrate_to_expiring_token(shop)
      end)

      reloaded = Shops.get_shop_by_url("reject-mig.myshopify.com")
      assert reloaded.access_token == "legacy"
      assert is_nil(reloaded.token_expires_at)
    end

    test "never retries — one attempt even when the host app enables retries globally" do
      original = Application.get_env(:shopifex, :req_options, [])
      Application.put_env(:shopifex, :req_options, original ++ [retry: :transient])
      on_exit(fn -> Application.put_env(:shopifex, :req_options, original) end)

      attempts = :counters.new(1, [:atomics])

      Req.Test.stub(Shopifex.ReqStub, fn conn ->
        :counters.add(attempts, 1, 1)
        conn |> Plug.Conn.put_status(503) |> Req.Test.json(%{"error" => "unavailable"})
      end)

      shop =
        Shops.create_shop(%{
          url: "no-retry-mig.myshopify.com",
          scope: "read_orders",
          access_token: "legacy",
          token_expires_at: nil
        })

      capture_log(fn ->
        assert {:error, {:migrate_failed, 503, _}} = Auth.migrate_to_expiring_token(shop)
      end)

      assert :counters.get(attempts, 1) == 1
    end

    test "returns :shop_not_found when the row disappears before the write" do
      parent = self()

      Req.Test.stub(Shopifex.ReqStub, fn conn ->
        send(parent, :migration_exchanged)
        Req.Test.json(conn, token_response())
      end)

      shop =
        Shops.create_shop(%{
          url: "vanishing-mig.myshopify.com",
          scope: "read_orders",
          access_token: "legacy",
          token_expires_at: nil
        })

      Shops.delete_shop(shop)

      assert {:error, :shop_not_found} = Auth.migrate_to_expiring_token(shop)
      assert_received :migration_exchanged
    end
  end

  defp start_task(task_supervisor, fun, opts \\ []) do
    task =
      Task.Supervisor.async_nolink(task_supervisor, fn ->
        receive do
          :run -> fun.()
        end
      end)

    if Keyword.get(opts, :start?, true), do: send(task.pid, :run)
    task
  end

  defp task_result(task) do
    ref = task.ref
    assert_receive {^ref, result}, 1_000
    Process.demonitor(ref, [:flush])
    result
  end
end
