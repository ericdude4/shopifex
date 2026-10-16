defmodule Shopifex.SessionToken do
  @moduledoc """
  Verifies Shopify App Bridge session tokens (`id_token`) directly.

  This is the embedded-app authentication primitive: a strict HS256 verify of
  the JWT Shopify signs with your app's API secret, checking that:

  - the signature is valid (HS256 only — no algorithm confusion),
  - the audience (`aud`) equals your app's API key,
  - the destination (`dest`) is a well-formed `*.myshopify.com` shop domain
    (`Shopifex.ShopDomain.valid?/1`; it matches the expected shop when one is
    supplied),
  - the issuer (`iss`) is `\#{dest}/admin`,
  - the token is within its (very short, ~60s) validity window.

  `:expired` is returned as a distinct error from other failures so callers can
  log routine expiries at `:info` (stale bfcache loads, clock skew) while
  treating signature/audience failures as genuine anomalies.

  Replaces the Guardian-based session-token handling used in Shopifex v2.

  ## Configuration

      config :shopifex,
        api_key: "your_api_key",
        secret: "your_api_secret"
  """

  @allowed_clock_skew_seconds 10

  @doc """
  Verify a Shopify session token. Returns `{:ok, claims}` or `{:error, reason}`.

  Pass the shop's `*.myshopify.com` URL as the second argument to additionally
  assert the token's `dest` matches that shop.
  """
  @spec verify(String.t()) :: {:ok, map()} | {:error, atom()}
  def verify(token) when is_binary(token), do: verify_token(token, nil)
  def verify(_token), do: {:error, :invalid_token}

  @spec verify(String.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def verify(token, shop_url) when is_binary(token) and is_binary(shop_url),
    do: verify_token(token, shop_url)

  def verify(_token, _shop_url), do: {:error, :invalid_token}

  defp verify_token(token, shop_url) do
    secret = Application.fetch_env!(:shopifex, :secret)
    api_key = Application.fetch_env!(:shopifex, :api_key)

    with true <- is_binary(secret) and secret != "",
         true <- is_binary(api_key) and api_key != "",
         {:ok, claims} <- verify_signature(token, secret),
         :ok <- validate_claims(claims, shop_url, api_key) do
      {:ok, claims}
    else
      false -> {:error, :missing_shopify_credentials}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_token}
    end
  rescue
    _ -> {:error, :invalid_token}
  end

  # Strict HS256 verify with the current secret, falling back to a rotated-out
  # `:old_secret` (when configured) so a secret rotation doesn't reject
  # in-flight session tokens still signed with the previous secret.
  defp verify_signature(token, secret) do
    secrets =
      case Application.get_env(:shopifex, :old_secret) do
        old when is_binary(old) and old != "" -> [secret, old]
        _ -> [secret]
      end

    Enum.reduce_while(secrets, {:error, :invalid_signature}, fn candidate, acc ->
      case JOSE.JWT.verify_strict(JOSE.JWK.from_oct(candidate), ["HS256"], token) do
        {true, %JOSE.JWT{fields: claims}, _jws} -> {:halt, {:ok, claims}}
        _ -> {:cont, acc}
      end
    end)
  end

  defp validate_claims(claims, shop_url, api_key) do
    # Embedded apps are authenticated against the shop's Shopify Admin identity.
    # Even if the merchant sells through a custom storefront domain, App Bridge
    # session tokens identify the shop by its canonical *.myshopify.com domain.
    expected_dest = if shop_url, do: "https://#{shop_url}"
    token_dest = claims["dest"]
    now = System.system_time(:second)

    cond do
      is_binary(expected_dest) && token_dest != expected_dest ->
        {:error, :invalid_destination}

      not valid_destination?(token_dest) ->
        {:error, :invalid_destination}

      not audience_matches?(claims["aud"], api_key) ->
        {:error, :invalid_audience}

      not expires_after?(claims["exp"], now) ->
        {:error, :expired}

      not usable_after?(claims["nbf"], now) ->
        {:error, :not_yet_valid}

      invalid_issuer?(claims["iss"], token_dest) ->
        {:error, :invalid_issuer}

      true ->
        :ok
    end
  end

  defp audience_matches?(audience, api_key) when is_binary(audience), do: audience == api_key
  defp audience_matches?(audience, api_key) when is_list(audience), do: api_key in audience
  defp audience_matches?(_, _), do: false

  # Same anchored pattern `AuthController.initialize_installation/2` applies to
  # the unsigned `shop` param, so a `dest` like `evil.example#.myshopify.com`
  # never reaches the token-exchange URL or `Shops.get_url/1`. Defence in
  # depth: `dest` is inside the signed JWT, so it takes the app secret to forge.
  defp valid_destination?("https://" <> shop_url), do: Shopifex.ShopDomain.valid?(shop_url)

  defp valid_destination?(_), do: false

  defp expires_after?(exp, now) when is_integer(exp), do: exp + @allowed_clock_skew_seconds > now
  defp expires_after?(_, _), do: false

  defp usable_after?(nil, _now), do: true

  defp usable_after?(nbf, now) when is_integer(nbf),
    do: nbf - @allowed_clock_skew_seconds <= now

  defp usable_after?(_, _), do: false

  defp invalid_issuer?(nil, _dest), do: false
  defp invalid_issuer?(issuer, dest) when is_binary(issuer), do: issuer != "#{dest}/admin"
  defp invalid_issuer?(_, _), do: true
end
