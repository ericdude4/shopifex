defmodule Shopifex.ChargeBindingTest do
  # async: false — one test rotates the global :secret/:old_secret app env,
  # which other async modules read for HMAC/session-token signing.
  use ExUnit.Case, async: false

  alias Shopifex.ChargeBinding

  test "sign and verify roundtrip with plan_id normalized to string" do
    payload = %{
      shop_url: "example.myshopify.com",
      plan_id: 123,
      redirect_after: "/dashboard"
    }

    signed = ChargeBinding.sign(payload)
    assert is_binary(signed)

    assert {:ok, verified} = ChargeBinding.verify(signed)
    assert verified.shop_url == "example.myshopify.com"
    assert verified.plan_id == "123"
    assert verified.redirect_after == "/dashboard"
  end

  test "verify fails on tampered token" do
    payload = %{
      shop_url: "example.myshopify.com",
      plan_id: "1",
      redirect_after: "/"
    }

    signed = ChargeBinding.sign(payload)
    tampered = signed <> "bad"

    assert {:error, :invalid} = ChargeBinding.verify(tampered)
  end

  test "verify fails on expired token" do
    payload = %{
      shop_url: "example.myshopify.com",
      plan_id: "1",
      redirect_after: "/"
    }

    signed = ChargeBinding.sign(payload)

    assert {:error, :expired} = ChargeBinding.verify(signed, max_age: -1)
  end

  test "verify falls back to :old_secret when primary secret changes" do
    prev_secret = Application.get_env(:shopifex, :secret)
    prev_old_secret = Application.get_env(:shopifex, :old_secret)

    # Token signed with original secret
    payload = %{
      shop_url: "rotate.myshopify.com",
      plan_id: "5",
      redirect_after: "/rotated"
    }

    signed = ChargeBinding.sign(payload)

    # Now rotate secret: old secret becomes the previous secret
    Application.put_env(:shopifex, :secret, "new_shiny_secret_1234567890123456")
    Application.put_env(:shopifex, :old_secret, prev_secret)

    on_exit(fn ->
      Application.put_env(:shopifex, :secret, prev_secret)

      if prev_old_secret do
        Application.put_env(:shopifex, :old_secret, prev_old_secret)
      else
        Application.delete_env(:shopifex, :old_secret)
      end
    end)

    assert {:ok, verified} = ChargeBinding.verify(signed)
    assert verified.shop_url == "rotate.myshopify.com"
    assert verified.plan_id == "5"
  end
end
