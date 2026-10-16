defmodule Shopifex.ChargeBinding do
  @moduledoc """
  Signs and verifies charge bindings for payment flows.

  Binds `{shop_url, plan_id, redirect_after}` cryptographically so that
  when Shopify redirects back to `/payment/complete`, the return-path
  can verify that the charge was initiated by this app for that specific
  shop and plan.
  """

  @salt "shopifex_charge_binding"
  @max_age_seconds 48 * 3600

  @doc """
  Signs a charge binding payload with the configured app secret.

  `plan_id` is normalized to a string.
  """
  @spec sign(map()) :: String.t()
  def sign(%{shop_url: shop_url, plan_id: plan_id, redirect_after: redirect_after}) do
    data = %{
      shop_url: to_string(shop_url),
      plan_id: to_string(plan_id),
      redirect_after: to_string(redirect_after)
    }

    Plug.Crypto.sign(primary_secret(), @salt, data)
  end

  @doc """
  Verifies a signed charge binding string.

  Checks against the primary app secret first, and falls back to `:old_secret`
  if configured, allowing seamless secret rotation.

  Returns `{:ok, payload}` or `{:error, reason}` where `reason` is `:invalid` or `:expired`.
  """
  @spec verify(term(), keyword()) :: {:ok, map()} | {:error, :invalid | :expired}
  def verify(signed, opts \\ [])

  def verify(signed, opts) when is_binary(signed) do
    max_age = Keyword.get(opts, :max_age, @max_age_seconds)

    secrets()
    |> Enum.reduce_while({:error, :invalid}, fn secret, _acc ->
      case Plug.Crypto.verify(secret, @salt, signed, max_age: max_age) do
        {:ok, data} -> {:halt, {:ok, data}}
        {:error, reason} -> {:cont, {:error, reason}}
      end
    end)
  end

  def verify(_signed, _opts), do: {:error, :invalid}

  defp primary_secret, do: Application.fetch_env!(:shopifex, :secret)

  defp secrets do
    case Application.get_env(:shopifex, :old_secret) do
      old when is_binary(old) and old != "" -> [primary_secret(), old]
      _ -> [primary_secret()]
    end
  end
end
