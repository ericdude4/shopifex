defmodule Shopifex.APITest do
  use Shopifex.DataCase, async: false
  import ExUnit.CaptureLog

  alias Shopifex.{API, Shops}

  setup do
    shop =
      Shops.create_shop(%{
        url: "api.myshopify.com",
        scope: "read_orders",
        access_token: "tok"
      })

    {:ok, shop: shop}
  end

  defp soon, do: DateTime.utc_now() |> DateTime.add(60, :second) |> DateTime.truncate(:second)
  defp later, do: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)
  defp past, do: DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)

  defp token_endpoint?(conn), do: String.contains?(conn.request_path, "/admin/oauth/access_token")

  test "defaults to the 2026-07 Admin API version" do
    previous = Application.fetch_env(:shopifex, :api_version)
    Application.delete_env(:shopifex, :api_version)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:shopifex, :api_version, value)
        :error -> Application.delete_env(:shopifex, :api_version)
      end
    end)

    assert API.api_version() == "2026-07"
  end

  test "uses a configured non-default API version in the request URL", %{shop: shop} do
    previous = Application.fetch_env(:shopifex, :api_version)
    Application.put_env(:shopifex, :api_version, "2027-01")

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:shopifex, :api_version, value)
        :error -> Application.delete_env(:shopifex, :api_version)
      end
    end)

    parent = self()

    Req.Test.stub(Shopifex.ReqStub, fn conn ->
      send(parent, {:request_path, conn.request_path})
      Req.Test.json(conn, %{"data" => %{}})
    end)

    API.graphql(shop, "{ shop { name } }")
    assert_received {:request_path, path}
    assert path == "/admin/api/2027-01/graphql.json"
  end

  test "returns {:ok, data} on a successful GraphQL response", %{shop: shop} do
    Req.Test.stub(Shopifex.ReqStub, fn conn ->
      Req.Test.json(conn, %{"data" => %{"shop" => %{"name" => "Test Shop"}}})
    end)

    assert {:ok, %{"shop" => %{"name" => "Test Shop"}}} = API.graphql(shop, "{ shop { name } }")
  end

  test "errors take precedence even when data is present", %{shop: shop} do
    Req.Test.stub(Shopifex.ReqStub, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{"shop" => nil},
        "errors" => [%{"message" => "Access denied"}]
      })
    end)

    assert {:error, [%{"message" => "Access denied"}]} = API.graphql(shop, "{ shop { name } }")
  end

  test "uses the configured API version in the request URL", %{shop: shop} do
    parent = self()

    Req.Test.stub(Shopifex.ReqStub, fn conn ->
      send(parent, {:request_path, conn.request_path})
      Req.Test.json(conn, %{"data" => %{}})
    end)

    API.graphql(shop, "{ shop { name } }")
    assert_received {:request_path, path}
    assert path == "/admin/api/#{API.api_version()}/graphql.json"
  end

  test "returns {:error, {status, body}} for a non-200/401 response", %{shop: shop} do
    Req.Test.stub(Shopifex.ReqStub, fn conn ->
      conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => "boom"})
    end)

    assert {:error, {500, %{"error" => "boom"}}} = API.graphql(shop, "{ shop { name } }")
  end

  test "returns a Req.TransportError struct on connection failure", %{shop: shop} do
    Req.Test.stub(Shopifex.ReqStub, fn conn ->
      Req.Test.transport_error(conn, :econnrefused)
    end)

    assert {:error, %Req.TransportError{reason: :econnrefused}} =
             API.graphql(shop, "{ shop { name } }")
  end

  test "omits the variables key from the request body when none are given", %{shop: shop} do
    parent = self()

    Req.Test.stub(Shopifex.ReqStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:body, Jason.decode!(body)})
      Req.Test.json(conn, %{"data" => %{}})
    end)

    API.graphql(shop, "{ shop { name } }")
    assert_received {:body, decoded}
    refute Map.has_key?(decoded, "variables")
  end

  test "includes the variables key when variables are given", %{shop: shop} do
    parent = self()

    Req.Test.stub(Shopifex.ReqStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:body, Jason.decode!(body)})
      Req.Test.json(conn, %{"data" => %{}})
    end)

    API.graphql(shop, "query($id: ID!) { node(id: $id) { id } }", %{id: "gid://1"})
    assert_received {:body, decoded}
    assert decoded["variables"] == %{"id" => "gid://1"}
  end

  test "req_options config takes precedence over the library's own Req options", %{shop: shop} do
    previous = Application.fetch_env(:shopifex, :req_options)

    Application.put_env(:shopifex, :req_options,
      plug: {Req.Test, Shopifex.ReqStub},
      headers: [{"x-shopify-access-token", "overridden"}]
    )

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:shopifex, :req_options, value)
        :error -> Application.delete_env(:shopifex, :req_options)
      end
    end)

    parent = self()

    Req.Test.stub(Shopifex.ReqStub, fn conn ->
      send(
        parent,
        {:access_token_header, Plug.Conn.get_req_header(conn, "x-shopify-access-token")}
      )

      Req.Test.json(conn, %{"data" => %{}})
    end)

    API.graphql(shop, "{ shop { name } }")
    assert_received {:access_token_header, ["overridden"]}
  end

  test "reactively refreshes once on 401 and retries the request" do
    shop =
      Shops.create_shop(%{
        url: "retry.myshopify.com",
        scope: "read_orders",
        access_token: "stale",
        # comfortably fresh so ensure_fresh_token does NOT proactively refresh —
        # the only refresh comes from the reactive 401 path.
        token_expires_at:
          DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second),
        refresh_token: "rt"
      })

    graphql_calls = :counters.new(1, [:atomics])

    Req.Test.stub(Shopifex.ReqStub, fn conn ->
      cond do
        String.contains?(conn.request_path, "/admin/oauth/access_token") ->
          Req.Test.json(conn, %{
            "access_token" => "fresh",
            "scope" => "read_orders",
            "expires_in" => 3600,
            "refresh_token" => "rt2",
            "refresh_token_expires_in" => 7_776_000
          })

        true ->
          n = :counters.get(graphql_calls, 1)
          :counters.add(graphql_calls, 1, 1)

          if n == 0 do
            conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{})
          else
            Req.Test.json(conn, %{"data" => %{"ok" => true}})
          end
      end
    end)

    assert {:ok, %{"ok" => true}} = API.graphql(shop, "{ ok }")
  end

  test "401 -> refresh ok -> 401 again returns {:error, {401, body}} after exactly one refresh" do
    shop =
      Shops.create_shop(%{
        url: "double-401.myshopify.com",
        scope: "read_orders",
        access_token: "stale",
        token_expires_at: later(),
        refresh_token: "rt"
      })

    graphql_calls = :counters.new(1, [:atomics])
    refresh_calls = :counters.new(1, [:atomics])

    Req.Test.stub(Shopifex.ReqStub, fn conn ->
      if token_endpoint?(conn) do
        :counters.add(refresh_calls, 1, 1)

        Req.Test.json(conn, %{
          "access_token" => "fresh",
          "scope" => "read_orders",
          "expires_in" => 3600,
          "refresh_token" => "rt2",
          "refresh_token_expires_in" => 7_776_000
        })
      else
        :counters.add(graphql_calls, 1, 1)
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"error" => "still bad"})
      end
    end)

    assert {:error, {401, %{"error" => "still bad"}}} = API.graphql(shop, "{ shop { name } }")
    assert :counters.get(graphql_calls, 1) == 2
    assert :counters.get(refresh_calls, 1) == 1
  end

  test "proactive refresh success sends the request with the NEW access token" do
    shop =
      Shops.create_shop(%{
        url: "proactive-success.myshopify.com",
        scope: "read_orders",
        access_token: "old",
        token_expires_at: soon(),
        refresh_token: "rt"
      })

    parent = self()

    Req.Test.stub(Shopifex.ReqStub, fn conn ->
      if token_endpoint?(conn) do
        Req.Test.json(conn, %{
          "access_token" => "brand_new_token",
          "scope" => "read_orders",
          "expires_in" => 3600,
          "refresh_token" => "rt2",
          "refresh_token_expires_in" => 7_776_000
        })
      else
        send(
          parent,
          {:access_token_header, Plug.Conn.get_req_header(conn, "x-shopify-access-token")}
        )

        Req.Test.json(conn, %{"data" => %{"ok" => true}})
      end
    end)

    assert {:ok, %{"ok" => true}} = API.graphql(shop, "{ ok }")
    assert_received {:access_token_header, ["brand_new_token"]}
  end

  test "proactive terminal refresh failure short-circuits without a GraphQL request" do
    shop =
      Shops.create_shop(%{
        url: "proactive-terminal.myshopify.com",
        scope: "read_orders",
        access_token: "old",
        token_expires_at: soon(),
        refresh_token: "rt",
        refresh_token_expires_at: past()
      })

    Req.Test.stub(Shopifex.ReqStub, fn _conn ->
      flunk("expected no HTTP request: an expired refresh_token should fail fast")
    end)

    assert {:error, {:token_refresh_failed, :refresh_token_expired}} =
             API.graphql(shop, "{ shop { name } }")
  end

  test "reactive terminal refresh failure returns token_refresh_failed instead of the raw 401" do
    shop =
      Shops.create_shop(%{
        url: "reactive-terminal.myshopify.com",
        scope: "read_orders",
        access_token: "stale",
        token_expires_at: later(),
        refresh_token: "spent_rt"
      })

    Req.Test.stub(Shopifex.ReqStub, fn conn ->
      if token_endpoint?(conn) do
        conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "invalid_grant"})
      else
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{})
      end
    end)

    log =
      capture_log(fn ->
        assert {:error, {:token_refresh_failed, {:refresh_failed, 400}}} =
                 API.graphql(shop, "{ shop { name } }")
      end)

    assert log =~ "Refresh token grant failed"
  end
end
