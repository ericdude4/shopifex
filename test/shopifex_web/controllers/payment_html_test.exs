defmodule ShopifexWeb.PaymentHTMLTest do
  use ShopifexWeb.ConnCase, async: true

  alias ShopifexWeb.PaymentHTML

  describe "price_label/1" do
    test "formats USD recurring monthly and annual" do
      monthly = %{price: "9.99", currency_code: "USD", type: "recurring_application_charge"}
      assert PaymentHTML.price_label(monthly) == "$9.99/month"

      annual = %{
        price: "99.00",
        currency_code: "USD",
        type: "recurring_application_charge",
        annual: true
      }

      assert PaymentHTML.price_label(annual) == "$99.00/year"
    end

    test "formats EUR and GBP symbols" do
      eur = %{price: "19.99", currency_code: "EUR", type: "recurring_application_charge"}
      assert PaymentHTML.price_label(eur) == "€19.99/month"

      gbp = %{price: "15.00", currency_code: "GBP", type: "recurring_application_charge"}
      assert PaymentHTML.price_label(gbp) == "£15.00/month"
    end

    test "formats non-symbol currencies with code prefix" do
      cad = %{price: "25.00", currency_code: "CAD", type: "recurring_application_charge"}
      assert PaymentHTML.price_label(cad) == "CAD 25.00/month"
    end

    test "formats one-time application charges" do
      one_time = %{price: "49.00", currency_code: "USD", type: "application_charge"}
      assert PaymentHTML.price_label(one_time) == "$49.00 one-time"
    end
  end

  describe "current_plan?/2" do
    test "checks matching grants against a grant list" do
      plan = %{grants: ["guard_a", "guard_b"]}

      assert PaymentHTML.current_plan?(["guard_b", "guard_a"], plan)
      refute PaymentHTML.current_plan?(["guard_a"], plan)
      refute PaymentHTML.current_plan?([], plan)
    end
  end

  describe "select_plan_path/1" do
    @shop %ShopifexDummy.Shop{url: "path.myshopify.com"}

    test "is the bare path when the page was authenticated with an id_token", %{conn: conn} do
      conn = Shopifex.Test.put_shopify_session(conn, @shop)

      assert PaymentHTML.select_plan_path(conn) == "/payment/select-plan"
    end

    test "carries a redirect_token bound to select-plan when there is no id_token", %{conn: conn} do
      conn = Shopifex.Plug.build_session(conn, @shop, nil)
      refute Shopifex.Plug.session_token(conn)

      %URI{path: "/payment/select-plan", query: query} =
        conn |> PaymentHTML.select_plan_path() |> URI.parse()

      assert %{"redirect_token" => token} = URI.decode_query(query)
      assert Shopifex.Plug.verify_redirect(token, "/payment/select-plan") == {:ok, @shop.url}
      assert Shopifex.Plug.verify_redirect(token, "/payment/show-plans") == :error
    end
  end
end
