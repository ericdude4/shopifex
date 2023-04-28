defmodule Shopifex.Guardian do
  # AppBridge frequently sends future `nbf`, and it causes `{:error, :token_not_yet_valid}`.
  # Accept few seconds clock skew to avoid this error.
  # 
  # see: https://github.com/Shopify/shopify_python_api/blob/master/shopify/session_token.py#L58-L60
  @allowed_drift Application.compile_env(:shopifex, :allowed_drift, 10_000)

  use Guardian,
    otp_app: :shopifex,
    issuer: {Application, :get_env, [:shopifex, :app_name]},
    secret_key: {Application, :get_env, [:shopifex, :secret]},
    allowed_algos: ["HS512", "HS256"],
    allowed_drift: @allowed_drift

  def subject_for_token(shop, _claims), do: {:ok, Shopifex.Shops.get_url(shop)}

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
