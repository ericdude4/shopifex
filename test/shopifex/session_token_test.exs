defmodule Shopifex.SessionTokenTest do
  # async: false — the ":old_secret" describe block mutates the global `:old_secret` app env.
  use ExUnit.Case, async: false

  alias Shopifex.SessionToken

  @secret "shpss_thisisafakesecret"
  @api_key "thisisafakeapikey"
  @shop "session-token-test.myshopify.com"

  defp sign(claims) do
    jwk = JOSE.JWK.from_oct(@secret)
    {_, token} = JOSE.JWT.sign(jwk, %{"alg" => "HS256"}, claims) |> JOSE.JWS.compact()
    token
  end

  defp valid_claims(overrides \\ %{}) do
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
  end

  test "accepts a valid token and returns its claims" do
    assert {:ok, claims} = SessionToken.verify(sign(valid_claims()), @shop)
    assert claims["dest"] == "https://#{@shop}"
  end

  test "accepts a valid token without a shop_url argument" do
    assert {:ok, _claims} = SessionToken.verify(sign(valid_claims()))
  end

  test "rejects a token signed with the wrong secret as invalid_signature" do
    jwk = JOSE.JWK.from_oct("a-totally-different-secret")
    {_, token} = JOSE.JWT.sign(jwk, %{"alg" => "HS256"}, valid_claims()) |> JOSE.JWS.compact()
    assert {:error, :invalid_signature} = SessionToken.verify(token, @shop)
  end

  test "returns :expired distinctly for an expired token" do
    now = System.system_time(:second)
    token = sign(valid_claims(%{"exp" => now - 120}))
    assert {:error, :expired} = SessionToken.verify(token, @shop)
  end

  test "rejects a mismatched destination" do
    token = sign(valid_claims())
    assert {:error, :invalid_destination} = SessionToken.verify(token, "other.myshopify.com")
  end

  test "rejects a non-myshopify destination" do
    token = sign(valid_claims(%{"dest" => "https://evil.example.com"}))
    assert {:error, :invalid_destination} = SessionToken.verify(token)
  end

  test "rejects a destination that only ends with .myshopify.com" do
    # `dest` is validated with the same anchored pattern as the install `shop`
    # param, so a suffix match alone (which `String.ends_with?/2` accepted) is
    # not enough to reach the token-exchange URL built from it.
    for dest <- [
          "https://evil.example#.myshopify.com",
          "https://evil.example/x?.myshopify.com",
          "https://.myshopify.com"
        ] do
      token = sign(valid_claims(%{"dest" => dest}))
      assert {:error, :invalid_destination} = SessionToken.verify(token)
    end
  end

  test "accepts a hyphenated, mixed-case shop handle" do
    token =
      sign(
        valid_claims(%{
          "dest" => "https://Shop-1.myshopify.com",
          "iss" => "https://Shop-1.myshopify.com/admin"
        })
      )

    assert {:ok, _claims} = SessionToken.verify(token)
  end

  test "rejects a wrong audience" do
    token = sign(valid_claims(%{"aud" => "someone-elses-api-key"}))
    assert {:error, :invalid_audience} = SessionToken.verify(token, @shop)
  end

  test "rejects a mismatched issuer" do
    token = sign(valid_claims(%{"iss" => "https://#{@shop}/not-admin"}))
    assert {:error, :invalid_issuer} = SessionToken.verify(token, @shop)
  end

  test "rejects non-binary input" do
    assert {:error, :invalid_token} = SessionToken.verify(nil)
    assert {:error, :invalid_token} = SessionToken.verify(123, @shop)
  end

  describe "10s clock-skew boundary" do
    test "accepts a token that expired 9s ago (inside the skew allowance)" do
      now = System.system_time(:second)
      token = sign(valid_claims(%{"exp" => now - 9}))
      assert {:ok, _claims} = SessionToken.verify(token, @shop)
    end

    test "rejects a token that expired 11s ago (outside the skew allowance)" do
      now = System.system_time(:second)
      token = sign(valid_claims(%{"exp" => now - 11}))
      assert {:error, :expired} = SessionToken.verify(token, @shop)
    end

    test "accepts a token usable 9s in the future (inside the skew allowance)" do
      now = System.system_time(:second)
      token = sign(valid_claims(%{"nbf" => now + 9}))
      assert {:ok, _claims} = SessionToken.verify(token, @shop)
    end

    test "rejects a token usable 11s in the future (outside the skew allowance)" do
      now = System.system_time(:second)
      token = sign(valid_claims(%{"nbf" => now + 11}))
      assert {:error, :not_yet_valid} = SessionToken.verify(token, @shop)
    end

    test "accepts a token with no nbf claim at all" do
      token = valid_claims() |> Map.delete("nbf") |> sign()
      assert {:ok, _claims} = SessionToken.verify(token, @shop)
    end
  end

  describe "secret rotation (:old_secret)" do
    @old_secret "shpss_previous_app_secret"

    setup do
      on_exit(fn -> Application.delete_env(:shopifex, :old_secret) end)
      :ok
    end

    test "accepts a token signed with the old secret only when :old_secret is configured" do
      jwk = JOSE.JWK.from_oct(@old_secret)
      {_, token} = JOSE.JWT.sign(jwk, %{"alg" => "HS256"}, valid_claims()) |> JOSE.JWS.compact()

      assert {:error, :invalid_signature} = SessionToken.verify(token, @shop)

      Application.put_env(:shopifex, :old_secret, @old_secret)
      assert {:ok, claims} = SessionToken.verify(token, @shop)
      assert claims["dest"] == "https://#{@shop}"
    end

    test "the current secret still verifies while :old_secret is configured" do
      Application.put_env(:shopifex, :old_secret, @old_secret)
      assert {:ok, _claims} = SessionToken.verify(sign(valid_claims()), @shop)
    end
  end
end
