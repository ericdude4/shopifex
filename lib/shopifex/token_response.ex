defmodule Shopifex.TokenResponse do
  @moduledoc """
  Builds the shop attrs map persisted from a decoded Shopify OAuth
  access-token response.

  Both the legacy authorization-code grant (`ShopifexWeb.AuthController`) and
  the managed-install token exchange (`Shopifex.Plug.ManagedInstall`) parse
  the same response shape and funnel through here, so token-lifecycle handling
  (`expires_in` / `refresh_token_expires_in` -> `*_expires_at`) isn't
  duplicated or left to drift between the two flows.

  Only a fixed set of known fields is read from `body` — unknown keys are
  dropped, never turned into atoms (no `String.to_atom/1` on external input).
  """

  @doc """
  Builds the atom-keyed shop attrs map for `shop_url` from a decoded Shopify
  OAuth access-token response body.

  Tolerates a response without `expires_in` / `refresh_token` (non-expiring
  tokens, used by older installs or test fixtures) — the expiry timestamps
  stay `nil`.
  """
  @spec shop_attrs(String.t(), map()) :: map()
  def shop_attrs(shop_url, body) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    scope_field = Shopifex.Shops.get_scope_field()

    %{
      url: shop_url,
      access_token: body["access_token"],
      token_expires_at: expires_at(now, body["expires_in"]),
      refresh_token: body["refresh_token"],
      refresh_token_expires_at: expires_at(now, body["refresh_token_expires_in"])
    }
    # `scope` is nullable and may be absent from the response — persist what
    # Shopify returned (possibly nil). A `|| ""` fallback here is dead on
    # arrival: a standard `cast/3` casts `""` back to nil via Ecto's default
    # `:empty_values`.
    |> Map.put(scope_field, body["scope"])
  end

  defp expires_at(_now, nil), do: nil
  defp expires_at(now, seconds) when is_integer(seconds), do: DateTime.add(now, seconds, :second)
end
