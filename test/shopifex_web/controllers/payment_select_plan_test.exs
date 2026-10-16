# The dummy router mounts `payment_routes/2` with the embedded default only.
# This router mounts it with `shopify_embedded: false`, so the non-embedded
# pipeline ([:shopifex_browser, :shopify_session], no CSP plug) has a home.
# Top-level so it does not inherit the ConnCase imports (Phoenix.ConnTest.get/3
# clashes with Phoenix.Router.get/3).
defmodule ShopifexWeb.PaymentSelectPlanTest.NonEmbeddedRouter do
  use Phoenix.Router, helpers: false
  import Plug.Conn
  import Phoenix.Controller
  require ShopifexWeb.Routes

  ShopifexWeb.Routes.pipelines()
  ShopifexWeb.Routes.payment_routes(ShopifexDummyWeb.PaymentController, shopify_embedded: false)
end

defmodule ShopifexWeb.PaymentSelectPlanTest do
  # The plans page's Select button POSTs `{plan_id, redirect_after}` and nothing
  # else. Inside the Shopify admin App Bridge attaches the Bearer `id_token`;
  # outside it, the page must carry its own credential on the route.
  use ShopifexWeb.ConnCase, async: false

  alias ShopifexWeb.PaymentSelectPlanTest.NonEmbeddedRouter

  @parsers Plug.Parsers.init(
             parsers: [:urlencoded, :multipart, :json],
             pass: ["*/*"],
             body_reader: {ShopifexWeb.CacheBodyReader, :read_body, []},
             json_decoder: Jason
           )
  @session Plug.Session.init(store: :cookie, key: "_shopifex_key", signing_salt: "qb1yL9WE")

  @select_plan_path "/payment/select-plan"
  @confirmation_url "https://confirm.example/charge"

  setup do
    shop =
      Shopifex.Shops.create_shop(%{
        url: "select-plan.myshopify.com",
        scope: "orders",
        access_token: "tok"
      })

    {:ok, plan} =
      Shopifex.Shops.create_plan(%{
        name: "Premium",
        price: "9.99",
        type: "recurring_application_charge",
        features: ["premium"],
        grants: ["premium"],
        usages: nil,
        test: true
      })

    {:ok, shop: shop, plan: plan}
  end

  # Endpoint-equivalent preparation, then straight into the non-embedded router.
  defp dispatch_non_embedded(conn) do
    conn
    |> Map.put(:secret_key_base, ShopifexDummyWeb.Endpoint.config(:secret_key_base))
    |> Plug.Conn.put_private(:phoenix_endpoint, ShopifexDummyWeb.Endpoint)
    |> Plug.Parsers.call(@parsers)
    |> Plug.Session.call(@session)
    |> NonEmbeddedRouter.call(NonEmbeddedRouter.init([]))
  end

  # Exactly what show_plans.html.heex sends: the plan id and redirect_after,
  # no token in the body.
  defp ui_payload(plan), do: Jason.encode!(%{plan_id: to_string(plan.id), redirect_after: "/"})

  # The `route` literal the page's inline script POSTs to, decoded from the
  # HTML-safe JSON the template emits.
  defp rendered_route(html) do
    assert [_, json] = Regex.run(~r/var route = ("[^"]*");/, html)
    Jason.decode!(json)
  end

  defp guard_redirect_location(conn) do
    [location] =
      conn
      |> Shopifex.Plug.PaymentGuard.call("premium")
      |> get_resp_header("location")

    location
  end

  defp stub_subscription_create(gid) do
    parent = self()

    Req.Test.stub(Shopifex.ReqStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:graphql, Jason.decode!(body)})

      Req.Test.json(conn, %{
        "data" => %{
          "appSubscriptionCreate" => %{
            "appSubscription" => %{"id" => gid},
            "confirmationUrl" => @confirmation_url,
            "userErrors" => []
          }
        }
      })
    end)
  end

  defp stub_shopify_unreachable do
    Req.Test.stub(Shopifex.ReqStub, fn _ -> flunk("must not reach Shopify without auth") end)
  end

  describe "payment_routes(shopify_embedded: false)" do
    test "the plans page reached via the guard's redirect_token can select a plan with the UI payload alone",
         %{shop: shop, plan: plan} do
      location =
        build_conn(:get, "/premium-route")
        |> Shopifex.Plug.build_session(shop, nil, "en")
        |> guard_redirect_location()

      plans = dispatch_non_embedded(Plug.Test.conn(:get, location))

      assert plans.status == 200
      assert plans.resp_body =~ "Payment options"
      assert Shopifex.Plug.current_shop(plans).id == shop.id
      # No App Bridge id_token anywhere on this page load...
      refute Shopifex.Plug.session_token(plans)

      # ...so the route carries a redirect_token bound to select-plan.
      route = rendered_route(plans.resp_body)
      %URI{path: @select_plan_path, query: query} = URI.parse(route)
      assert %{"redirect_token" => token} = URI.decode_query(query)
      assert Shopifex.Plug.verify_redirect(token, @select_plan_path) == {:ok, shop.url}

      stub_subscription_create("gid://shopify/AppSubscription/424242")

      # Recycle the page's cookies onto the POST the way the browser would and
      # send the exact UI payload with no synthetic auth.
      selected =
        Plug.Test.conn(:post, route, ui_payload(plan))
        |> Plug.Test.recycle_cookies(plans)
        |> put_req_header("content-type", "application/json")
        |> dispatch_non_embedded()

      assert selected.status == 200
      assert %{"confirmation_url" => @confirmation_url} = Jason.decode!(selected.resp_body)
      assert Shopifex.Plug.current_shop(selected).id == shop.id
      assert_received {:graphql, %{"query" => "mutation appSubscriptionCreate" <> _}}

      # The charge is bound to this shop and plan for complete_payment/2.
      assert {:ok, bound} =
               424_242 |> Shopifex.RedirectAfterAgent.get() |> Shopifex.ChargeBinding.verify()

      assert bound.shop_url == shop.url
      assert bound.plan_id == to_string(plan.id)
    end

    test "the UI payload alone, with no redirect_token on the route, is still refused",
         %{plan: plan} do
      stub_shopify_unreachable()

      selected =
        Plug.Test.conn(:post, @select_plan_path, ui_payload(plan))
        |> put_req_header("content-type", "application/json")
        |> dispatch_non_embedded()

      assert selected.halted
      assert Shopifex.Plug.current_shop(selected) == nil
      refute selected.resp_body =~ "confirmation_url"
    end

    test "the plans-page redirect_token is not accepted at select-plan, nor the reverse (path binding)",
         %{shop: shop, plan: plan} do
      location =
        build_conn(:get, "/premium-route")
        |> Shopifex.Plug.build_session(shop, nil, "en")
        |> guard_redirect_location()

      %URI{query: query} = URI.parse(location)
      plans_token = URI.decode_query(query)["redirect_token"]
      assert is_binary(plans_token)

      stub_shopify_unreachable()

      selected =
        Plug.Test.conn(
          :post,
          @select_plan_path <> "?" <> URI.encode_query(%{"redirect_token" => plans_token}),
          ui_payload(plan)
        )
        |> put_req_header("content-type", "application/json")
        |> dispatch_non_embedded()

      assert selected.halted
      assert Shopifex.Plug.current_shop(selected) == nil
      refute selected.resp_body =~ "confirmation_url"

      # And the select-plan token minted for the page does not open the plans
      # page (or anything else) on its own.
      plans = dispatch_non_embedded(Plug.Test.conn(:get, location))
      %URI{query: select_query} = plans.resp_body |> rendered_route() |> URI.parse()
      select_token = URI.decode_query(select_query)["redirect_token"]

      replayed =
        dispatch_non_embedded(
          Plug.Test.conn(
            :get,
            "/payment/show-plans?" <> URI.encode_query(%{"redirect_token" => select_token})
          )
        )

      assert replayed.halted
      assert Shopifex.Plug.current_shop(replayed) == nil
      refute replayed.resp_body =~ "Payment options"
    end
  end

  describe "payment_routes/2 embedded default" do
    test "the UI payload with App Bridge's Bearer id_token creates the charge", %{
      shop: shop,
      plan: plan
    } do
      stub_subscription_create("gid://shopify/AppSubscription/4242")

      selected =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header(
          "authorization",
          "Bearer " <> Shopifex.Test.sign_session_token(shop.url)
        )
        |> post(@select_plan_path, ui_payload(plan))

      assert selected.status == 200
      assert %{"confirmation_url" => @confirmation_url} = Jason.decode!(selected.resp_body)
      assert Shopifex.Plug.current_shop(selected).id == shop.id
      assert_received {:graphql, %{"query" => "mutation appSubscriptionCreate" <> _}}
    end

    test "the plans page reached with an id_token renders the bare route (no redirect_token)",
         %{shop: shop} do
      # The guard forwards the id_token as `token`, so App Bridge authenticates
      # the Select fetch and the page needs no credential of its own.
      location =
        build_conn(:get, "/premium-route")
        |> Shopifex.Test.put_shopify_session(shop)
        |> guard_redirect_location()

      assert location =~ "token="

      plans = get(build_conn(), location)

      assert html_response(plans, 200) =~ "Payment options"
      assert Shopifex.Plug.session_token(plans)
      assert rendered_route(plans.resp_body) == @select_plan_path
      refute plans.resp_body =~ "redirect_token="
    end
  end
end
