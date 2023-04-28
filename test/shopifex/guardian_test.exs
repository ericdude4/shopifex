defmodule Shopifex.GuardianTest do
  use ExUnit.Case

  describe "allowed_drift defaults" do
    test "accepts tokens with nbf up to 10s in the future" do
      future =
        DateTime.utc_now()
        |> DateTime.add(9)
        |> DateTime.to_unix()

      {:ok, jwt} = Guardian.Token.Jwt.create_token(Shopifex.Guardian, %{"nbf" => future})

      assert {:ok, _claims} = Shopifex.Guardian.decode_and_verify(jwt)
    end

    test "accepts tokens with exp up to 10s in the past" do
      past =
        DateTime.utc_now()
        |> DateTime.add(-9)
        |> DateTime.to_unix()

      {:ok, jwt} = Guardian.Token.Jwt.create_token(Shopifex.Guardian, %{"exp" => past})

      assert {:ok, _claims} = Shopifex.Guardian.decode_and_verify(jwt)
    end

    test "rejects tokens with nbf more than 10s in the future" do
      future =
        DateTime.utc_now()
        |> DateTime.add(11)
        |> DateTime.to_unix()

      {:ok, jwt} = Guardian.Token.Jwt.create_token(Shopifex.Guardian, %{"nbf" => future})

      assert {:error, :token_not_yet_valid} = Shopifex.Guardian.decode_and_verify(jwt)
    end

    test "rejects tokens with exp more than 10s in the past" do
      past =
        DateTime.utc_now()
        |> DateTime.add(-11)
        |> DateTime.to_unix()

      {:ok, jwt} = Guardian.Token.Jwt.create_token(Shopifex.Guardian, %{"exp" => past})

      assert {:error, :token_expired} = Shopifex.Guardian.decode_and_verify(jwt)
    end
  end
end
