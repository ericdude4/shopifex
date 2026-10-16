defmodule Shopifex.ShopDomain do
  @moduledoc """
  Validates the `shop` query param Shopify sends on every install/auth
  request against Shopify's own `*.myshopify.com` pattern.

  The pattern is anchored at both ends so a crafted value like
  `evil.example/x?.myshopify.com` or `attacker.myshopify.com.evil.example`
  cannot pass — using an unanchored match to gate an external redirect is an
  open-redirect vector (the redirect host is attacker-controlled).
  """

  @pattern ~r/\A[a-zA-Z0-9][a-zA-Z0-9\-]*\.myshopify\.com\z/

  @doc "Returns `true` if `shop_url` is a well-formed `*.myshopify.com` domain."
  @spec valid?(String.t()) :: boolean()
  def valid?(shop_url) when is_binary(shop_url), do: Regex.match?(@pattern, shop_url)
  def valid?(_shop_url), do: false
end
