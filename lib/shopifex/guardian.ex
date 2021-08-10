defmodule Shopifex.Guardian do
  use Guardian,
    otp_app: :shopifex,
    issuer: Application.get_env(:shopifex, :app_name),
    secret_key: Application.get_env(:shopifex, :secret),
    allowed_algos: ["HS512", "HS256"]

  def subject_for_token(%{url: url}, _claims), do: {:ok, url}

  @doc """
  Since app bridge tokens are only short lived, we generate
  a new longer lived token for the rest of the session
  lifetime. These tokens contain the shop url in the
  "sub" claim.
  """
  def resource_from_claims(%{"dest" => "https://" <> shop_url}) do
    shop = Shopifex.Shops.get_shop_by_url(shop_url)
    {:ok, shop}
  end

  def resource_from_claims(%{"sub" => shop_url}) do
    shop = Shopifex.Shops.get_shop_by_url(shop_url)
    {:ok, shop}
  end

  def resource_from_claims(_claims) do
    {:error, :reason_for_error}
  end
end
