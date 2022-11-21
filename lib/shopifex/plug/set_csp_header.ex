defmodule Shopifex.Plug.SetCSPHeader do
  @moduledoc """
  Adds Content-Security-Policy response header to the provided `Plug.Conn` in order to securely
  load embedded application in the Shopify admin panel.

  Read more here: https://shopify.dev/apps/store/security/iframe-protection#embedded-apps
  """
  defexception message: "an error occurred when attempting to set CSP headers"

  @shopify_unified_admin_url "https://admin.shopify.com"

  def init(options) do
    # initialize options
    options
  end

  @spec call(conn :: Plug.Conn.t(), opts :: any()) :: Plug.Conn.t() | none()
  def call(conn, _) do
    with {:ok, shop} <- get_current_shop(conn),
         url = Shopifex.Shops.get_url(shop) do
      allowed_frame_ancestors = [@shopify_unified_admin_url, "https://#{url}"]

      Plug.Conn.put_resp_header(
        conn,
        "content-security-policy",
        "frame-ancestors #{Enum.join(allowed_frame_ancestors, " ")};"
      )
    else
      {:error, :no_current_shop} ->
        raise(__MODULE__,
          message:
            "Cannot set CSP header without shop loaded in session. Ensure that this plug is being called on a `conn` which has been passed through the `Shopifex.Plug.ShopifySession` plug."
        )
    end
  end

  defp get_current_shop(conn) do
    case Shopifex.Plug.current_shop(conn) do
      nil -> {:error, :no_current_shop}
      shop -> {:ok, shop}
    end
  end
end
