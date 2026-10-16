defmodule ShopifexWeb.AuthControllerTest do
  use ShopifexWeb.ConnCase, async: true

  import Shopifex.Test

  test "new shop is redirected to install", %{conn: conn} do
    conn =
      get(conn, "/initialize-installation", %{
        "shop" => "shopifex.myshopify.com"
      })

    assert conn.status == 302
    [location] = Plug.Conn.get_resp_header(conn, "location")
    assert location =~ "https://shopifex.myshopify.com/admin/oauth/authorize"
  end

  test "locale is an optional parameter in auth flow", %{conn: conn} do
    query =
      %{
        "shop" => "shopifex.myshopify.com",
        "hmac" => "E0D42CC61A5D3A685D3A7AE652E5BFB0F6D05DDDBE446CA6AC496FFA3FA5488B"
      }
      |> URI.encode_query()

    conn = get(conn, "/auth" <> "?#{query}")

    [location] = Plug.Conn.get_resp_header(conn, "location")

    assert location =~ "https://shopifex.myshopify.com/admin/oauth/authorize?"

    # Assert the decoded query rather than an exact string — the params are
    # URI-encoded, so key order and escaping are not part of the contract.
    params = location |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert params["client_id"] == "thisisafakeapikey"
    assert params["scope"] == "orders"
    assert params["redirect_uri"] == "https://shopifex-dummy.com/auth/install"

    assert conn.status == 302
  end

  test "store selector is rendered with a flash error if an invalid url is passed", %{conn: conn} do
    conn =
      get(conn, "/initialize-installation", %{
        "shop" => "invalid.shopify.url"
      })

    body = html_response(conn, 200)
    assert body =~ "Install"
    assert body =~ "Invalid shop URL"
  end

  describe "initialize_installation validates the shop domain (open redirect)" do
    # `ShopDomain.valid?/1` is anchored end-to-end, so none of these payloads
    # (which merely contain ".myshopify.com" somewhere) can reach the external
    # redirect built from `shop_url`.
    test "rejects shop params that only contain .myshopify.com as a substring", %{conn: conn} do
      for shop_url <- [
            "evil.example/x?.myshopify.com",
            "attacker.myshopify.com.evil.example",
            "evil.example#.myshopify.com"
          ] do
        conn =
          get(conn, "/initialize-installation", %{
            "shop" => shop_url
          })

        body = html_response(conn, 200)
        assert body =~ "Invalid shop URL"
        assert Plug.Conn.get_resp_header(conn, "location") == []
      end
    end

    test "a non-binary state param is dropped instead of raising", %{conn: conn} do
      for query <- ["state[a]=b", "state[]=x"] do
        conn = get(conn, "/initialize-installation?shop=shopifex-valid.myshopify.com&" <> query)

        location = redirected_to(conn)
        assert location =~ "https://shopifex-valid.myshopify.com/admin/oauth/authorize?"

        params = location |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
        assert params["state"] == ""
      end
    end

    test "a valid shop still redirects to the Shopify OAuth authorize URL", %{conn: conn} do
      conn =
        get(conn, "/initialize-installation", %{
          "shop" => "shopifex-valid.myshopify.com"
        })

      assert redirected_to(conn) =~
               "https://shopifex-valid.myshopify.com/admin/oauth/authorize?"
    end
  end

  describe "managed installation through the generated /auth route" do
    setup do
      parent = self()

      # Stub the whole round trip: RFC 8693 token exchange (scope matches the
      # configured `:scopes` so the :shopify_session pipeline's EnsureScopes
      # passes) plus GraphQL webhook configuration.
      Req.Test.stub(Shopifex.ReqStub, fn conn ->
        if String.ends_with?(conn.request_path, "/admin/oauth/access_token") do
          Req.Test.json(conn, %{
            "access_token" => "integration_token",
            "scope" => "orders",
            "expires_in" => 3600,
            "refresh_token" => "integration_refresh",
            "refresh_token_expires_in" => 7_776_000
          })
        else
          {:ok, body, conn} = Plug.Conn.read_body(conn)

          if Jason.decode!(body)["query"] =~ "webhookSubscriptionCreate" do
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

      :ok
    end

    test "GET /auth?id_token=...&shop=... installs the shop and lands in the app", %{conn: conn} do
      shop_url = "integration.myshopify.com"
      id_token = valid_session_token(shop_url)

      query =
        URI.encode_query(%{"id_token" => id_token, "shop" => shop_url, "host" => "aG9zdA=="})

      conn = get(conn, "/auth" <> "?#{query}")

      # auth/2 redirects to the app root, carrying the embedded-context params
      # (shop/host/id_token) so App Bridge can re-initialize on the landing page
      # and the landing route's :shopify_session can authenticate the hop.
      location = redirected_to(conn)
      assert %URI{path: "/", query: redirect_query} = URI.parse(location)
      redirect_params = URI.decode_query(redirect_query)
      assert redirect_params["shop"] == shop_url
      assert redirect_params["host"] == "aG9zdA=="
      assert redirect_params["id_token"] == id_token

      # Webhooks are configured on first install, end-to-end through the pipeline.
      assert_received :webhook_created

      shop = Shopifex.Shops.get_shop_by_url(shop_url)
      assert shop.access_token == "integration_token"
      assert shop.scope == "orders"
      assert shop.refresh_token == "integration_refresh"
    end
  end

  describe "auth/2 without an id_token forwards Shopify's complete signed query" do
    test "the landing route gets the full original query, including hmac and timestamp", %{
      conn: conn
    } do
      shop_url = "legacy-no-app-bridge.myshopify.com"

      Shopifex.Shops.create_shop(%{url: shop_url, scope: "orders", access_token: "tok"})

      params = %{"shop" => shop_url, "timestamp" => to_string(System.system_time(:second))}
      full = Map.put(params, "hmac", sign_query_hmac(params))

      conn = get(conn, "/auth" <> "?#{URI.encode_query(full)}")

      location = redirected_to(conn)
      assert %URI{path: "/", query: redirect_query} = URI.parse(location)
      redirect_params = URI.decode_query(redirect_query)

      assert redirect_params["shop"] == shop_url
      assert redirect_params["hmac"] == full["hmac"]
      assert redirect_params["timestamp"] == full["timestamp"]
      refute Map.has_key?(redirect_params, "id_token")
    end
  end

  describe "legacy OAuth code grant" do
    # GET /auth/install and /auth/update go through :validate_install_hmac, so
    # the request has to carry a real signature.
    defp signed_auth_path(action, params) do
      full = Map.put(params, "hmac", sign_query_hmac(params))
      "/auth/#{action}?" <> URI.encode_query(full)
    end

    defp admin_apps_url(shop_url) do
      "https://#{shop_url}/admin/apps/#{Application.fetch_env!(:shopifex, :api_key)}"
    end

    test "install exchanges the code and creates the shop", %{conn: conn} do
      shop_url = "legacy-install.myshopify.com"
      parent = self()

      Req.Test.stub(Shopifex.ReqStub, fn req_conn ->
        send(parent, :code_exchanged)

        Req.Test.json(req_conn, %{
          "access_token" => "legacy_token",
          "scope" => "read_orders"
        })
      end)

      conn =
        get(conn, signed_auth_path("install", %{"code" => "abc123", "shop" => shop_url}))

      assert_received :code_exchanged
      assert redirected_to(conn) == admin_apps_url(shop_url)

      shop = Shopifex.Shops.get_shop_by_url(shop_url)
      assert shop.access_token == "legacy_token"
      assert shop.scope == "read_orders"
      assert shop.token_expires_at == nil
      assert shop.refresh_token == nil
      assert shop.refresh_token_expires_at == nil
    end

    test "install requests an expiring token and persists the token lifecycle", %{conn: conn} do
      shop_url = "legacy-install-expiring.myshopify.com"
      before_request = DateTime.utc_now()

      Req.Test.stub(Shopifex.ReqStub, fn req_conn ->
        if String.ends_with?(req_conn.request_path, "/admin/oauth/access_token") do
          assert Plug.Conn.get_req_header(req_conn, "content-type") ==
                   ["application/x-www-form-urlencoded"]

          {:ok, raw_body, req_conn} = Plug.Conn.read_body(req_conn)
          decoded = URI.decode_query(raw_body)

          assert decoded["expiring"] == "1"
          assert decoded["client_id"] == Application.fetch_env!(:shopifex, :api_key)
          assert decoded["client_secret"] == Application.fetch_env!(:shopifex, :secret)
          assert decoded["code"] == "abc123"

          Req.Test.json(req_conn, %{
            "access_token" => "legacy_expiring_token",
            "scope" => "read_orders",
            "expires_in" => 3600,
            "refresh_token" => "legacy_refresh",
            "refresh_token_expires_in" => 7_776_000
          })
        else
          # Post-install webhook reconciliation (Shopifex.Shops.configure_webhooks/1).
          Req.Test.json(req_conn, %{"data" => %{"webhookSubscriptions" => %{"edges" => []}}})
        end
      end)

      conn = get(conn, signed_auth_path("install", %{"code" => "abc123", "shop" => shop_url}))
      assert redirected_to(conn) == admin_apps_url(shop_url)

      shop = Shopifex.Shops.get_shop_by_url(shop_url)
      assert shop.access_token == "legacy_expiring_token"
      assert shop.refresh_token == "legacy_refresh"

      assert_in_delta DateTime.diff(shop.token_expires_at, before_request, :second), 3600, 5

      assert_in_delta DateTime.diff(shop.refresh_token_expires_at, before_request, :second),
                      7_776_000,
                      5
    end

    test "install raises Shopifex.InstallError when Shopify rejects the code", %{conn: conn} do
      Req.Test.stub(Shopifex.ReqStub, fn req_conn ->
        req_conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{"error" => "invalid_request"})
      end)

      path =
        signed_auth_path("install", %{"code" => "bad", "shop" => "legacy-bad.myshopify.com"})

      assert_raise Shopifex.InstallError, fn -> get(conn, path) end
    end

    test "update exchanges the code and updates the existing shop", %{conn: conn} do
      shop_url = "legacy-update.myshopify.com"

      Shopifex.Shops.create_shop(%{
        url: shop_url,
        scope: "read_orders",
        access_token: "stale_token"
      })

      Req.Test.stub(Shopifex.ReqStub, fn req_conn ->
        Req.Test.json(req_conn, %{
          "access_token" => "rotated_token",
          "scope" => "read_orders,write_orders"
        })
      end)

      conn = get(conn, signed_auth_path("update", %{"code" => "def456", "shop" => shop_url}))

      assert redirected_to(conn) == admin_apps_url(shop_url)

      shop = Shopifex.Shops.get_shop_by_url(shop_url)
      assert shop.access_token == "rotated_token"
      assert shop.scope == "read_orders,write_orders"
      assert shop.token_expires_at == nil
      assert shop.refresh_token == nil
      assert shop.refresh_token_expires_at == nil
    end

    test "update requests an expiring token and persists the token lifecycle", %{conn: conn} do
      shop_url = "legacy-update-expiring.myshopify.com"
      before_request = DateTime.utc_now()

      Shopifex.Shops.create_shop(%{
        url: shop_url,
        scope: "read_orders",
        access_token: "stale_token"
      })

      Req.Test.stub(Shopifex.ReqStub, fn req_conn ->
        Req.Test.json(req_conn, %{
          "access_token" => "rotated_expiring_token",
          "scope" => "read_orders,write_orders",
          "expires_in" => 3600,
          "refresh_token" => "rotated_refresh",
          "refresh_token_expires_in" => 7_776_000
        })
      end)

      conn = get(conn, signed_auth_path("update", %{"code" => "def456", "shop" => shop_url}))
      assert redirected_to(conn) == admin_apps_url(shop_url)

      shop = Shopifex.Shops.get_shop_by_url(shop_url)
      assert shop.access_token == "rotated_expiring_token"
      assert shop.refresh_token == "rotated_refresh"

      assert_in_delta DateTime.diff(shop.token_expires_at, before_request, :second), 3600, 5

      assert_in_delta DateTime.diff(shop.refresh_token_expires_at, before_request, :second),
                      7_776_000,
                      5
    end

    test "an unexpected key in the OAuth response is never atomized", %{conn: conn} do
      shop_url = "legacy-whitelist.myshopify.com"
      key = "some_unexpected_key_#{System.unique_integer([:positive])}"

      Req.Test.stub(Shopifex.ReqStub, fn req_conn ->
        Req.Test.json(req_conn, %{
          "access_token" => "whitelisted",
          "scope" => "read_orders",
          key => "ignored"
        })
      end)

      conn = get(conn, signed_auth_path("install", %{"code" => "xyz", "shop" => shop_url}))
      assert redirected_to(conn) == admin_apps_url(shop_url)

      shop = Shopifex.Shops.get_shop_by_url(shop_url)
      assert shop.access_token == "whitelisted"

      # The response key was never atomized — it doesn't exist as an atom.
      assert_raise ArgumentError, fn -> String.to_existing_atom(key) end
    end
  end
end
