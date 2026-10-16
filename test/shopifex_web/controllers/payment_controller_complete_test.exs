defmodule ShopifexWeb.PaymentControllerCompleteTest do
  # Covers complete_payment/2: charge binding verification, verify_charge/3,
  # loud logs on cache miss/forgery, and grant creation.
  use ShopifexWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias Shopifex.Shops

  setup %{conn: conn} do
    shop =
      Shops.create_shop(%{url: "complete.myshopify.com", scope: "orders", access_token: "tok"})

    {:ok, plan} =
      Shops.create_plan(%{
        name: "Basic",
        price: "9.99",
        type: "recurring_application_charge",
        features: ["premium"],
        grants: ["premium"],
        usages: nil,
        test: true
      })

    {:ok, conn: conn, shop: shop, plan: plan}
  end

  defp stub_active_subscription(status) do
    Req.Test.stub(Shopifex.ReqStub, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{
          "node" => %{
            "status" => status
          }
        }
      })
    end)
  end

  describe "redirect-cache miss" do
    test "logs an actionable error and responds with a 403 Conn (not the bare tuple)", %{
      conn: conn,
      shop: shop,
      plan: plan
    } do
      {result, log} =
        with_log(fn ->
          ShopifexDummyWeb.PaymentController.complete_payment(conn, %{
            "charge_id" => "9999999",
            "plan_id" => to_string(plan.id),
            "shop" => shop.url
          })
        end)

      assert %Plug.Conn{status: 403} = result
      assert log =~ "no redirect-after entry"
      assert log =~ "redirect_after_agent"
    end

    test "GET /payment/complete with an unknown charge_id returns 403, never a raised 500", %{
      conn: conn,
      shop: shop,
      plan: plan
    } do
      {conn, _log} =
        with_log(fn ->
          get(conn, "/payment/complete", %{
            "charge_id" => "9999999",
            "plan_id" => to_string(plan.id),
            "shop" => shop.url
          })
        end)

      assert conn.status == 403
    end
  end

  describe "non-integer charge_id" do
    test "returns 403 without crashing on non-integer charge_id", %{
      conn: conn,
      shop: shop,
      plan: plan
    } do
      {conn, log} =
        with_log(fn ->
          ShopifexDummyWeb.PaymentController.complete_payment(conn, %{
            "charge_id" => "invalid_charge_id",
            "plan_id" => to_string(plan.id),
            "shop" => shop.url
          })
        end)

      assert conn.status == 403
      assert log =~ "invalid non-integer charge_id"
    end
  end

  describe "non-string params" do
    # Plug parses bracket syntax (`plan_id[x]=y`) into maps/lists. None of these
    # may consume the binding: a scanner who knows a pending charge id and the
    # public shop domain must not be able to make the merchant's own
    # confirmation land on "no entry".
    test "a map-valued plan_id with the correct shop returns 403 and keeps the binding", %{
      conn: conn,
      shop: shop,
      plan: plan
    } do
      charge_id = 111_222_333
      ShopifexWeb.PaymentController.bind_charge(shop, plan, charge_id, "/dashboard")

      {result, _log} =
        with_log(fn ->
          get(conn, "/payment/complete?charge_id=#{charge_id}&shop=#{shop.url}&plan_id[x]=y")
        end)

      assert result.status == 403

      stub_active_subscription("ACTIVE")

      legit_conn =
        ShopifexDummyWeb.PaymentController.complete_payment(conn, %{
          "charge_id" => to_string(charge_id),
          "plan_id" => to_string(plan.id),
          "shop" => shop.url
        })

      assert legit_conn.status in [301, 302]
      assert Enum.find(Shops.list_grants(), &(&1.charge_id == charge_id))
    end

    test "a list-valued plan_id, map-valued shop or map-valued charge_id returns 403 without raising",
         %{conn: conn, shop: shop, plan: plan} do
      charge_id = 222_333_444
      ShopifexWeb.PaymentController.bind_charge(shop, plan, charge_id, "/dashboard")

      for query <- [
            "charge_id=#{charge_id}&shop=#{shop.url}&plan_id[]=#{plan.id}",
            "charge_id=#{charge_id}&shop[x]=y&plan_id=#{plan.id}",
            "charge_id[x]=y&shop=#{shop.url}&plan_id=#{plan.id}",
            "charge_id[]=#{charge_id}&shop=#{shop.url}&plan_id=#{plan.id}"
          ] do
        {result, _log} = with_log(fn -> get(conn, "/payment/complete?" <> query) end)
        assert result.status == 403
      end

      # The binding is still there for the legitimate confirmation.
      stub_active_subscription("ACTIVE")

      legit_conn =
        ShopifexDummyWeb.PaymentController.complete_payment(conn, %{
          "charge_id" => to_string(charge_id),
          "plan_id" => to_string(plan.id),
          "shop" => shop.url
        })

      assert legit_conn.status in [301, 302]
      assert Enum.find(Shops.list_grants(), &(&1.charge_id == charge_id))
    end
  end

  describe "raise after the binding was popped" do
    test "a plan deleted while the charge was pending re-raises but restores the binding", %{
      conn: conn,
      shop: shop,
      plan: plan
    } do
      charge_id = 333_444_555
      ShopifexWeb.PaymentController.bind_charge(shop, plan, charge_id, "/dashboard")

      # The default `get_plan/1` is `Shops.get_plan!/1`, which raises once the
      # row is gone — after `store.get/1` already consumed the binding.
      ShopifexDummy.Repo.delete!(plan)

      assert_raise Ecto.NoResultsError, fn ->
        with_log(fn ->
          ShopifexDummyWeb.PaymentController.complete_payment(conn, %{
            "charge_id" => to_string(charge_id),
            "plan_id" => to_string(plan.id),
            "shop" => shop.url
          })
        end)
      end

      assert Shopifex.RedirectAfterAgent.get(charge_id) != nil
    end
  end

  describe "charge binding verification" do
    test "plain redirect string in store (legacy) is rejected with 403 and actionable log", %{
      conn: conn,
      shop: shop,
      plan: plan
    } do
      charge_id = 12345
      Shopifex.RedirectAfterAgent.set(charge_id, "/legacy-redirect")

      {result, log} =
        with_log(fn ->
          ShopifexDummyWeb.PaymentController.complete_payment(conn, %{
            "charge_id" => to_string(charge_id),
            "plan_id" => to_string(plan.id),
            "shop" => shop.url
          })
        end)

      assert result.status == 403
      assert log =~ "invalid charge binding"
      assert log =~ "bind_charge/4"

      # Restoring an already-invalid blob is a no-op (it's exactly what was
      # already stored), but complete_payment must not drop it either way.
      assert Shopifex.RedirectAfterAgent.get(charge_id) == "/legacy-redirect"
    end

    test "mismatched shop in return-url returns 403, restores the entry, and the legitimate request still succeeds",
         %{
           conn: conn,
           shop: shop,
           plan: plan
         } do
      charge_id = 23456
      ShopifexWeb.PaymentController.bind_charge(shop, plan, charge_id, "/dashboard")

      {result, log} =
        with_log(fn ->
          ShopifexDummyWeb.PaymentController.complete_payment(conn, %{
            "charge_id" => to_string(charge_id),
            "plan_id" => to_string(plan.id),
            "shop" => "other-attacker.myshopify.com"
          })
        end)

      assert result.status == 403
      assert log =~ "charge binding mismatch"

      # Entry is restored: charge ids are sequential-looking, so a third party
      # scanning them with an arbitrary shop/plan must not be able to make the
      # legitimate merchant's own confirmation land on "no entry" (dropped grant).
      # (Not read here via `get/1` first — that call is itself one-shot and would
      # consume the very entry this test is proving survives.)
      stub_active_subscription("ACTIVE")

      legit_conn =
        ShopifexDummyWeb.PaymentController.complete_payment(conn, %{
          "charge_id" => to_string(charge_id),
          "plan_id" => to_string(plan.id),
          "shop" => shop.url
        })

      assert legit_conn.status in [301, 302]
      assert Enum.find(Shops.list_grants(), &(&1.charge_id == charge_id))
    end

    test "mismatched plan in return-url returns 403, restores the entry, and the legitimate request still succeeds",
         %{
           conn: conn,
           shop: shop,
           plan: plan
         } do
      charge_id = 34567
      ShopifexWeb.PaymentController.bind_charge(shop, plan, charge_id, "/dashboard")

      {result, log} =
        with_log(fn ->
          ShopifexDummyWeb.PaymentController.complete_payment(conn, %{
            "charge_id" => to_string(charge_id),
            "plan_id" => "99999",
            "shop" => shop.url
          })
        end)

      assert result.status == 403
      assert log =~ "charge binding mismatch"

      stub_active_subscription("ACTIVE")

      legit_conn =
        ShopifexDummyWeb.PaymentController.complete_payment(conn, %{
          "charge_id" => to_string(charge_id),
          "plan_id" => to_string(plan.id),
          "shop" => shop.url
        })

      assert legit_conn.status in [301, 302]
      assert Enum.find(Shops.list_grants(), &(&1.charge_id == charge_id))
    end
  end

  describe "charge verification and grant creation" do
    test "happy path: active charge creates grant and redirects to Shopify admin", %{
      conn: conn,
      shop: shop,
      plan: plan
    } do
      charge_id = 45678
      stub_active_subscription("ACTIVE")
      ShopifexWeb.PaymentController.bind_charge(shop, plan, charge_id, "/dashboard")

      conn =
        ShopifexDummyWeb.PaymentController.complete_payment(conn, %{
          "charge_id" => to_string(charge_id),
          "plan_id" => to_string(plan.id),
          "shop" => shop.url
        })

      assert conn.status in [301, 302]
      [location] = Plug.Conn.get_resp_header(conn, "location")
      assert location =~ "/admin/apps/"
      assert location =~ "/dashboard"

      [grant] = Shops.list_grants()
      assert grant.charge_id == charge_id
      assert grant.grants == ["premium"]

      # Entry was consumed
      assert Shopifex.RedirectAfterAgent.get(charge_id) == nil
    end

    test "verify_charge returning error: returns 403, logs info, and restores store entry", %{
      conn: conn,
      shop: shop,
      plan: plan
    } do
      charge_id = 56789
      stub_active_subscription("PENDING")
      ShopifexWeb.PaymentController.bind_charge(shop, plan, charge_id, "/dashboard")

      conn =
        ShopifexDummyWeb.PaymentController.complete_payment(conn, %{
          "charge_id" => to_string(charge_id),
          "plan_id" => to_string(plan.id),
          "shop" => shop.url
        })

      assert conn.status == 403
      assert conn.resp_body =~ "charge not active"

      # Entry was restored so merchant can retry after approving
      restored_blob = Shopifex.RedirectAfterAgent.get(charge_id)
      assert is_binary(restored_blob)
      assert {:ok, %{shop_url: url}} = Shopifex.ChargeBinding.verify(restored_blob)
      assert url == shop.url
    end

    test "changeset error on create_grant restores store entry and raises", %{
      conn: conn,
      shop: shop,
      plan: plan
    } do
      charge_id = 67890
      stub_active_subscription("ACTIVE")
      ShopifexWeb.PaymentController.bind_charge(shop, plan, charge_id, "/dashboard")

      # First create grant with same charge_id if unique or simulate changeset error
      # Dummy app grant schema doesn't have unique constraint on charge_id, so we can mock create_grant
      # by defining a temporary test payment guard or stubbing
      defmodule FailingPaymentGuard do
        use Shopifex.PaymentGuard

        @impl Shopifex.PaymentGuard
        def create_grant(_shop, _plan, _charge_id) do
          changeset =
            ShopifexDummy.Shops.Grant.changeset(%ShopifexDummy.Shops.Grant{}, %{})
            |> Ecto.Changeset.add_error(:charge_id, "is invalid")

          {:error, changeset}
        end
      end

      prev_guard = Application.get_env(:shopifex, :payment_guard)
      Application.put_env(:shopifex, :payment_guard, FailingPaymentGuard)

      on_exit(fn ->
        Application.put_env(:shopifex, :payment_guard, prev_guard)
      end)

      assert_raise RuntimeError, ~r/Grant changeset rejected attributes/, fn ->
        ShopifexDummyWeb.PaymentController.complete_payment(conn, %{
          "charge_id" => to_string(charge_id),
          "plan_id" => to_string(plan.id),
          "shop" => shop.url
        })
      end

      # Store entry must be restored
      restored_blob = Shopifex.RedirectAfterAgent.get(charge_id)
      assert is_binary(restored_blob)
    end
  end

  describe "with a persistent Shopifex.RedirectAfter.Ecto store" do
    setup do
      previous = Application.get_env(:shopifex, :redirect_after_agent)
      Application.put_env(:shopifex, :redirect_after_agent, Shopifex.RedirectAfter.Ecto)

      on_exit(fn ->
        if previous do
          Application.put_env(:shopifex, :redirect_after_agent, previous)
        else
          Application.delete_env(:shopifex, :redirect_after_agent)
        end
      end)

      :ok
    end

    test "select_plan's redirect survives to complete_payment and the grant is created", %{
      conn: conn,
      shop: shop,
      plan: plan
    } do
      charge_id = "4019552312"
      stub_active_subscription("ACTIVE")

      # select_plan calls bind_charge/4
      :ok = ShopifexWeb.PaymentController.bind_charge(shop, plan, charge_id, "/")

      conn =
        ShopifexDummyWeb.PaymentController.complete_payment(conn, %{
          "charge_id" => charge_id,
          "plan_id" => to_string(plan.id),
          "shop" => shop.url
        })

      # after_payment redirects into the Shopify admin (not {:error, :forbidden}).
      assert conn.status in [301, 302]

      [grant] = Shops.list_grants()
      assert grant.charge_id == String.to_integer(charge_id)
      assert grant.grants == ["premium"]

      # one-shot: the redirect entry was consumed
      assert Shopifex.RedirectAfter.Ecto.get(charge_id) == nil
    end
  end
end
