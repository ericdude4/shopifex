defmodule Shopifex.Plug.EnsureScopes do
  @moduledoc """
  Ensures that the shop currently loaded in the session has all of the scopes
  defined under `config :shopifex, scopes: "foo"` (or the `:required_scopes`
  plug option).

  Both the required and the granted scope lists are normalised with
  `Shopifex.Scopes.split/1`: whitespace around scope names is ignored and empty
  segments are dropped, so an empty (or `nil`) `:scopes` config requires nothing.

  ## Behaviour on a scope mismatch

  For managed-install apps (the 3.0 default) access scopes are declared in your
  `shopify.app.toml` `[access_scopes]` and granted by Shopify at install/update —
  redirecting merchants into a legacy OAuth re-authorization is the wrong default.
  So a scope mismatch **fails with an actionable error** by default rather than
  redirecting.

  Choose the behaviour with the `:on_missing_scopes` plug option (or the
  `config :shopifex, :ensure_scopes_on_missing` application setting; the plug
  option wins):

    * `:raise` (default) — raise `Shopifex.RuntimeError` naming the missing scopes.
      Reconcile scopes through your app config; Shopify re-grants them on the next
      managed install/update.
    * `:redirect` — legacy behaviour: render a page that redirects the shop to the
      Shopify OAuth update flow. Use this only for apps still relying on OAuth.

  ## Examples

      # default: fail with an actionable message
      plug Shopifex.Plug.EnsureScopes

      # opt back into the legacy OAuth-update redirect
      plug Shopifex.Plug.EnsureScopes, on_missing_scopes: :redirect
  """
  import Plug.Conn
  import Phoenix.Controller
  require Logger

  def init(options), do: options

  def call(conn, opts \\ []) do
    case Shopifex.Plug.current_shop(conn) do
      nil ->
        raise(
          Shopifex.RuntimeError,
          """
          `Shopifex.Plug.EnsureScopes` must be placed in the pipeline after a plug which places a shop in the session; such as `Shopifex.Plug.ShopifySession` or `Shopifex.Plug.ShopifyWebhook`
          """
        )

      shop ->
        required_scopes =
          if Keyword.has_key?(opts, :required_scopes) do
            Keyword.get(opts, :required_scopes)
          else
            Application.get_env(:shopifex, :scopes)
          end

        case Shopifex.Scopes.missing(required_scopes, Shopifex.Shops.get_scope(shop)) do
          [] -> conn
          missing_scopes -> handle_missing_scopes(conn, shop, missing_scopes, opts)
        end
    end
  end

  defp handle_missing_scopes(conn, shop, missing_scopes, opts) do
    case Keyword.get(opts, :on_missing_scopes, configured_default()) do
      :redirect ->
        legacy_oauth_redirect(conn, shop, missing_scopes, opts)

      _raise ->
        raise(Shopifex.RuntimeError, missing_scopes_message(shop, missing_scopes))
    end
  end

  defp configured_default do
    Application.get_env(:shopifex, :ensure_scopes_on_missing, :raise)
  end

  defp missing_scopes_message(shop, missing_scopes) do
    """
    Shop #{Shopifex.Shops.get_url(shop)} is missing required scopes #{inspect(missing_scopes)}.

    For managed-install apps, declare access scopes in your `shopify.app.toml`
    `[access_scopes]` and deploy your app config — Shopify grants the scopes on the
    next managed install/update. Do not redirect merchants into legacy OAuth.

    To opt into the legacy OAuth-update redirect instead, pass
    `on_missing_scopes: :redirect` to `Shopifex.Plug.EnsureScopes`.
    """
  end

  # Legacy behaviour — render a page that redirects the shop to Shopify's OAuth
  # update flow so the merchant re-authorizes with the expanded scope set.
  defp legacy_oauth_redirect(conn, shop, missing_scopes, opts) do
    Logger.info(
      "Shop #{Shopifex.Shops.get_url(shop)} is missing required scopes #{inspect(missing_scopes)}, initiating legacy OAuth update"
    )

    base_required_scopes = Shopifex.Scopes.split(Application.get_env(:shopifex, :scopes))

    all_scopes_to_request = Enum.join(missing_scopes ++ base_required_scopes, ",")

    message = Keyword.get(opts, :message)

    query =
      URI.encode_query(%{
        "client_id" => Application.fetch_env!(:shopifex, :api_key),
        "scope" => all_scopes_to_request,
        "redirect_uri" => Application.fetch_env!(:shopifex, :reinstall_uri)
      })

    reinstall_url =
      "https://#{Shopifex.Shops.get_url(shop)}/admin/oauth/authorize?#{query}"

    conn
    |> put_view(ShopifexWeb.PageHTML)
    |> put_root_layout(html: false)
    |> put_layout(html: {ShopifexWeb.Layouts, :app})
    |> render("redirect.html", redirect_location: reinstall_url, message: message)
    |> halt()
  end
end
