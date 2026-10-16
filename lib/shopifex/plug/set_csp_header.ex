defmodule Shopifex.Plug.SetCSPHeader do
  @moduledoc """
  Adds Content-Security-Policy response header to the provided `Plug.Conn` in order to securely
  load embedded application in the Shopify admin panel.

  Read more here: https://shopify.dev/apps/store/security/iframe-protection#embedded-apps
  """
  defexception message: "an error occurred when attempting to set CSP headers"

  @shopify_unified_admin_url "https://admin.shopify.com"

  @spec init(options :: Plug.opts()) :: Plug.opts()
  def init(options) do
    # initialize options
    options
  end

  @spec call(conn :: Plug.Conn.t(), opts :: Plug.opts()) :: Plug.Conn.t() | none()
  def call(conn, _) do
    case get_current_shop(conn) do
      {:ok, shop} ->
        # admin.shopify.com (unified admin) is always allowed to frame the app.
        # The shop's own myshopify host is added only when it's a clean hostname,
        # so a malformed/tampered stored URL can't inject extra CSP directives
        # (e.g. a stray `;` ending `frame-ancestors` early).
        allowed_frame_ancestors =
          [@shopify_unified_admin_url | shop_frame_ancestor(Shopifex.Shops.get_url(shop))]

        csp_header =
          {"content-security-policy",
           "frame-ancestors #{Enum.join(allowed_frame_ancestors, " ")};"}

        Plug.Conn.prepend_resp_headers(conn, [csp_header])

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

  # Only treat the stored shop URL as a frame ancestor when it's a bare hostname
  # (letters/digits/dots/hyphens). Anything else — a scheme, path, whitespace, or
  # a CSP-significant character — is dropped rather than interpolated.
  defp shop_frame_ancestor(url) when is_binary(url) do
    if Regex.match?(~r/\A[a-z0-9][a-z0-9.\-]*\z/i, url), do: ["https://#{url}"], else: []
  end

  defp shop_frame_ancestor(_), do: []
end
