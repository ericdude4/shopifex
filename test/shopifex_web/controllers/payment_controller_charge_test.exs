defmodule ShopifexWeb.PaymentControllerChargeTest do
  use Shopifex.DataCase, async: false

  import Phoenix.ConnTest

  alias Shopifex.Shops

  @endpoint ShopifexDummyWeb.Endpoint

  # Signs a query-HMAC so the request passes the `:shopify_session` pipeline,
  # the same way a real Shopify admin-embedded request would.
  defp signed_select_plan_query_string(shop_url) do
    query = %{"shop" => shop_url, "timestamp" => to_string(System.system_time(:second))}
    hmac = Shopifex.Test.sign_query_hmac(query)
    URI.encode_query(Map.put(query, "hmac", hmac))
  end

  setup do
    shop =
      Shops.create_shop(%{url: "billing.myshopify.com", scope: "orders", access_token: "tok"})

    {:ok, shop: shop}
  end

  # Captures the full GraphQL request body (query + variables) so tests can
  # assert both the mutation shape and the variables Shopify actually receives.
  defp stub_charge(mutation_field, charge_field, gid) do
    parent = self()

    Req.Test.stub(Shopifex.ReqStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:graphql, Jason.decode!(body)})

      Req.Test.json(conn, %{
        "data" => %{
          mutation_field => %{
            charge_field => %{"id" => gid},
            "confirmationUrl" => "https://confirm.example/charge",
            "userErrors" => []
          }
        }
      })
    end)
  end

  defp assert_no_idempotent(query) do
    refute query =~ "@idempotent", "Shopify does not document @idempotent for billing mutations"
  end

  describe "appSubscriptionCreate (recurring)" do
    test "monthly plan passes lineItems as a variable with the EVERY_30_DAYS interval", %{
      shop: shop
    } do
      stub_charge(
        "appSubscriptionCreate",
        "appSubscription",
        "gid://shopify/AppSubscription/4019552312"
      )

      plan = %{
        id: 1,
        name: "Basic",
        price: "9.99",
        type: "recurring_application_charge",
        test: true
      }

      assert {:ok,
              %{"id" => "4019552312", "confirmation_url" => "https://confirm.example/charge"}} =
               ShopifexDummyWeb.PaymentController.create_charge(shop, plan)

      assert_received {:graphql, %{"query" => query, "variables" => variables}}
      assert query =~ "appSubscriptionCreate"
      # lineItems is a GraphQL variable, not interpolated into the query string.
      assert query =~ "lineItems: $lineItems"
      refute query =~ "appRecurringPricingDetails"
      assert_no_idempotent(query)

      assert [%{"plan" => %{"appRecurringPricingDetails" => pricing}}] = variables["lineItems"]
      assert pricing["interval"] == "EVERY_30_DAYS"
      assert pricing["price"] == %{"amount" => "9.99", "currencyCode" => "USD"}
      assert variables["trialDays"] == 0
    end

    test "annual plan uses the ANNUAL interval", %{shop: shop} do
      stub_charge("appSubscriptionCreate", "appSubscription", "gid://shopify/AppSubscription/7")

      plan = %{
        id: 2,
        name: "Pro",
        price: "99.00",
        type: "recurring_application_charge",
        annual: true,
        test: true
      }

      assert {:ok, %{"id" => "7"}} = ShopifexDummyWeb.PaymentController.create_charge(shop, plan)
      assert_received {:graphql, %{"variables" => variables}}

      assert [%{"plan" => %{"appRecurringPricingDetails" => %{"interval" => "ANNUAL"}}}] =
               variables["lineItems"]
    end

    test "passes trialDays through", %{shop: shop} do
      stub_charge("appSubscriptionCreate", "appSubscription", "gid://shopify/AppSubscription/8")

      plan = %{
        id: 3,
        name: "Trial",
        price: "10.00",
        type: "recurring_application_charge",
        trial_days: 14,
        test: true
      }

      assert {:ok, _} = ShopifexDummyWeb.PaymentController.create_charge(shop, plan)
      assert_received {:graphql, %{"query" => query, "variables" => variables}}
      assert query =~ "$trialDays: Int!"
      assert variables["trialDays"] == 14
    end

    test "normalizes replacement_behavior into the AppSubscriptionReplacementBehavior enum", %{
      shop: shop
    } do
      stub_charge("appSubscriptionCreate", "appSubscription", "gid://shopify/AppSubscription/9")

      plan = %{
        id: 4,
        name: "Upgrade",
        price: "20.00",
        type: "recurring_application_charge",
        replacement_behavior: :apply_immediately,
        test: true
      }

      assert {:ok, _} = ShopifexDummyWeb.PaymentController.create_charge(shop, plan)
      assert_received {:graphql, %{"query" => query, "variables" => variables}}
      assert query =~ "$replacementBehavior: AppSubscriptionReplacementBehavior"
      assert variables["replacementBehavior"] == "APPLY_IMMEDIATELY"
    end

    test "omits replacementBehavior (null) when the plan has none", %{shop: shop} do
      stub_charge("appSubscriptionCreate", "appSubscription", "gid://shopify/AppSubscription/10")

      plan = %{
        id: 5,
        name: "Plain",
        price: "5.00",
        type: "recurring_application_charge",
        test: true
      }

      assert {:ok, _} = ShopifexDummyWeb.PaymentController.create_charge(shop, plan)
      assert_received {:graphql, %{"variables" => variables}}
      assert variables["replacementBehavior"] == nil
    end

    test "merges a discount into the default line item's pricing details", %{shop: shop} do
      stub_charge("appSubscriptionCreate", "appSubscription", "gid://shopify/AppSubscription/11")

      plan = %{
        id: 6,
        name: "Discounted",
        price: "30.00",
        type: "recurring_application_charge",
        discount: %{value: %{percentage: 0.2}, durationLimitInIntervals: 3},
        test: true
      }

      assert {:ok, _} = ShopifexDummyWeb.PaymentController.create_charge(shop, plan)
      assert_received {:graphql, %{"variables" => variables}}
      assert [%{"plan" => %{"appRecurringPricingDetails" => pricing}}] = variables["lineItems"]

      assert pricing["discount"] == %{
               "value" => %{"percentage" => 0.2},
               "durationLimitInIntervals" => 3
             }
    end

    test "a caller-supplied :line_items list (multiple items / usage) overrides the default", %{
      shop: shop
    } do
      stub_charge("appSubscriptionCreate", "appSubscription", "gid://shopify/AppSubscription/12")

      line_items = [
        %{
          plan: %{
            appRecurringPricingDetails: %{
              price: %{amount: "10.00", currencyCode: "USD"},
              interval: "EVERY_30_DAYS"
            }
          }
        },
        %{
          plan: %{
            appUsagePricingDetails: %{
              terms: "$1 per 100 emails",
              cappedAmount: %{amount: "100.00", currencyCode: "USD"}
            }
          }
        }
      ]

      plan = %{
        id: 7,
        name: "Metered",
        price: "10.00",
        type: "recurring_application_charge",
        line_items: line_items,
        test: true
      }

      assert {:ok, _} = ShopifexDummyWeb.PaymentController.create_charge(shop, plan)
      assert_received {:graphql, %{"variables" => variables}}
      assert length(variables["lineItems"]) == 2
      assert [_, %{"plan" => %{"appUsagePricingDetails" => usage}}] = variables["lineItems"]
      assert usage["terms"] == "$1 per 100 emails"
    end

    test "honors a custom currency_code on the recurring line item", %{shop: shop} do
      stub_charge("appSubscriptionCreate", "appSubscription", "gid://shopify/AppSubscription/13")

      plan = %{
        id: 9,
        name: "Euro",
        price: "9.99",
        type: "recurring_application_charge",
        currency_code: "EUR",
        test: true
      }

      assert {:ok, _} = ShopifexDummyWeb.PaymentController.create_charge(shop, plan)
      assert_received {:graphql, %{"variables" => variables}}
      assert [%{"plan" => %{"appRecurringPricingDetails" => pricing}}] = variables["lineItems"]
      assert pricing["price"]["currencyCode"] == "EUR"
    end

    test "upcases a string-form replacement_behavior", %{shop: shop} do
      stub_charge("appSubscriptionCreate", "appSubscription", "gid://shopify/AppSubscription/14")

      plan = %{
        id: 10,
        name: "Standard",
        price: "9.99",
        type: "recurring_application_charge",
        replacement_behavior: "standard",
        test: true
      }

      assert {:ok, _} = ShopifexDummyWeb.PaymentController.create_charge(shop, plan)
      assert_received {:graphql, %{"variables" => variables}}
      assert variables["replacementBehavior"] == "STANDARD"
    end

    test "surfaces userErrors from Shopify", %{shop: shop} do
      Req.Test.stub(Shopifex.ReqStub, fn conn ->
        Req.Test.json(conn, %{
          "data" => %{
            "appSubscriptionCreate" => %{
              "appSubscription" => nil,
              "confirmationUrl" => nil,
              "userErrors" => [%{"field" => ["price"], "message" => "is invalid"}]
            }
          }
        })
      end)

      plan = %{id: 8, name: "Bad", price: "x", type: "recurring_application_charge", test: true}

      assert {:error, [%{"message" => "is invalid"}]} =
               ShopifexDummyWeb.PaymentController.create_charge(shop, plan)
    end
  end

  describe "appPurchaseOneTimeCreate (one-time)" do
    test "passes a MoneyInput price and sends no @idempotent directive", %{shop: shop} do
      stub_charge(
        "appPurchaseOneTimeCreate",
        "appPurchaseOneTime",
        "gid://shopify/AppPurchaseOneTime/55"
      )

      plan = %{id: 9, name: "Lifetime", price: "390.00", type: "application_charge", test: true}

      assert {:ok, %{"id" => "55", "confirmation_url" => "https://confirm.example/charge"}} =
               ShopifexDummyWeb.PaymentController.create_charge(shop, plan)

      assert_received {:graphql, %{"query" => query, "variables" => variables}}
      assert query =~ "appPurchaseOneTimeCreate"
      assert query =~ "$price: MoneyInput!"
      assert_no_idempotent(query)
      assert variables["price"] == %{"amount" => "390.00", "currencyCode" => "USD"}
    end

    test "honors a custom currency_code on the one-time price", %{shop: shop} do
      stub_charge(
        "appPurchaseOneTimeCreate",
        "appPurchaseOneTime",
        "gid://shopify/AppPurchaseOneTime/56"
      )

      plan = %{
        id: 11,
        name: "Lifetime EUR",
        price: "390.00",
        type: "application_charge",
        currency_code: "EUR",
        test: true
      }

      assert {:ok, _} = ShopifexDummyWeb.PaymentController.create_charge(shop, plan)
      assert_received {:graphql, %{"variables" => variables}}
      assert variables["price"]["currencyCode"] == "EUR"
    end
  end

  describe "select_plan/2 and bind_charge/4" do
    test "select_plan binds the charge and returns 200 JSON", %{shop: shop} do
      {:ok, plan} =
        Shops.create_plan(%{
          name: "Plan 100",
          price: "10.00",
          type: "recurring_application_charge",
          features: ["feat"],
          grants: ["g100"],
          test: true
        })

      stub_charge(
        "appSubscriptionCreate",
        "appSubscription",
        "gid://shopify/AppSubscription/888123"
      )

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_private(:shopifex, %{shop: shop})

      resp =
        ShopifexDummyWeb.PaymentController.select_plan(conn, %{
          "plan_id" => to_string(plan.id),
          "redirect_after" => "/after-select"
        })

      assert resp.status == 200

      assert %{"id" => "888123", "confirmation_url" => "https://confirm.example/charge"} =
               Jason.decode!(resp.resp_body)

      binding_blob = Shopifex.RedirectAfterAgent.get(888_123)
      assert is_binary(binding_blob)
      assert {:ok, verified} = Shopifex.ChargeBinding.verify(binding_blob)
      assert verified.shop_url == shop.url
      assert verified.plan_id == to_string(plan.id)
      assert verified.redirect_after == "/after-select"
    end

    test "select_plan responds with 422 JSON when create_charge returns an error", %{shop: shop} do
      {:ok, plan} =
        Shops.create_plan(%{
          name: "Error Plan",
          price: "10.00",
          type: "recurring_application_charge",
          features: ["feat"],
          grants: ["g_err"],
          test: true
        })

      Req.Test.stub(Shopifex.ReqStub, fn conn ->
        Req.Test.json(conn, %{
          "data" => %{
            "appSubscriptionCreate" => %{
              "appSubscription" => nil,
              "confirmationUrl" => nil,
              "userErrors" => [%{"field" => ["price"], "message" => "is invalid"}]
            }
          }
        })
      end)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_private(:shopifex, %{shop: shop})

      resp =
        ShopifexDummyWeb.PaymentController.select_plan(conn, %{
          "plan_id" => to_string(plan.id),
          "redirect_after" => "/after-err"
        })

      assert resp.status == 422

      assert %{"errors" => [%{"field" => ["price"], "message" => "is invalid"}]} =
               Jason.decode!(resp.resp_body)
    end

    test "router: a 502 from Shopify's GraphQL API is normalised to 422 JSON, not a 500", %{
      shop: shop
    } do
      {:ok, plan} =
        Shops.create_plan(%{
          name: "Gateway Error Plan",
          price: "10.00",
          type: "recurring_application_charge",
          features: ["feat"],
          grants: ["g_502"],
          test: true
        })

      Req.Test.stub(Shopifex.ReqStub, fn conn ->
        conn |> Plug.Conn.put_status(502) |> Req.Test.json(%{"error" => "bad gateway"})
      end)

      query_string = signed_select_plan_query_string(shop.url)

      conn =
        build_conn()
        |> post("/payment/select-plan?" <> query_string, %{
          "plan_id" => to_string(plan.id),
          "redirect_after" => "/after-502"
        })

      assert conn.status == 422
      assert %{"errors" => [%{"message" => message}]} = Jason.decode!(conn.resp_body)
      assert message =~ "502"
    end

    test "router: a transport error from Shopify's GraphQL API is normalised to 422 JSON, not a 500",
         %{shop: shop} do
      {:ok, plan} =
        Shops.create_plan(%{
          name: "Transport Error Plan",
          price: "10.00",
          type: "recurring_application_charge",
          features: ["feat"],
          grants: ["g_transport"],
          test: true
        })

      Req.Test.stub(Shopifex.ReqStub, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      query_string = signed_select_plan_query_string(shop.url)

      conn =
        build_conn()
        |> post("/payment/select-plan?" <> query_string, %{
          "plan_id" => to_string(plan.id),
          "redirect_after" => "/after-transport"
        })

      assert conn.status == 422
      assert %{"errors" => [%{"message" => message}]} = Jason.decode!(conn.resp_body)
      assert message =~ "econnrefused"
    end
  end
end
