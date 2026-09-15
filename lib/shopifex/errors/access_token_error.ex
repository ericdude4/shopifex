defmodule Shopifex.AccessTokenError do
  @moduledoc """
  Raised when a usable access token could not be obtained for a shop, for
  example because the expiring offline access token has expired and the
  refresh token was rejected by Shopify. The shop must go through the OAuth
  flow again (see `Shopifex.Plug.EnsureAccessToken`).
  """
  defexception [:message, :shop_url, :reason]

  @impl true
  def exception(opts) do
    shop_url = Keyword.get(opts, :shop_url)
    reason = Keyword.get(opts, :reason)

    message =
      Keyword.get(
        opts,
        :message,
        "Unable to obtain a valid Shopify access token for #{shop_url}: #{inspect(reason)}"
      )

    %__MODULE__{message: message, shop_url: shop_url, reason: reason}
  end
end
