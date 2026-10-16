defmodule ShopifexWeb.LiveSession do
  # To avoid making LiveView a dependency of the entire application, we'll
  # silence this warning. At runtime, the LiveView module will be available
  # if the application is using LiveView.
  @compile {:no_warn_undefined, Phoenix.Component}

  @moduledoc """
  Helpers and hooks for integrating LiveView with Shopifex.

  Note that LiveView session keys are `"shop_url"` and `"session_token"`
  (in Shopifex 2.x the key was `"current_shop"`).
  """

  @doc """
  Get options that should be passed to `live_session`.

  This is useful for integrating with other tools that require a custom `live_session`,
  like `beacon_live_admin`. For example:

  ```elixir
  beacon_live_admin ShopifexWeb.LiveSession.opts(...beacon_opts) do
    ...
  end
  ```
  """
  def opts(custom_opts \\ []) do
    on_mount = {__MODULE__, :assign_shop_to_socket}
    session = {__MODULE__, :put_shop_in_session, []}

    custom_opts
    |> Keyword.update(:on_mount, on_mount, &([on_mount] ++ List.wrap(&1)))
    |> Keyword.put(:session, session)
  end

  @doc """
  Return a map of session values to include in the liveview session. This
  will be merged with other session values and available in the on_mount.

  Only the shop's URL is serialized (not the shop struct) — the LiveView session
  is signed but **not encrypted**, so it is readable client-side; storing the
  struct would leak `access_token` / `refresh_token`. `on_mount` reloads the shop
  from the URL server-side.
  """
  def put_shop_in_session(conn) do
    session_token = Shopifex.Plug.session_token(conn)

    shop_url =
      case Shopifex.Plug.current_shop(conn) do
        nil -> nil
        shop -> Shopifex.Shops.get_url(shop)
      end

    %{"session_token" => session_token, "shop_url" => shop_url}
  end

  @doc """
  LiveView on_mount hooks for Shopify apps.

  ## `:assign_shop_to_socket` (default)

  Assigns `current_shop` and `session_token` from session to socket assigns.
  Use with the standard `shopifex_live_session` macro.

  ## `:embedded`

  Simplified hook for embedded Shopify apps where third-party cookies are
  blocked. Reads the shop from the session (set during the HTTP request by
  `put_shop_in_session/1`) and does NOT require tokens in URLs or LiveSocket
  connect params. Redirects to `/auth` (respecting `path_prefix`) if no shop is found.

  ### How it works

  1. HTTP request arrives with `id_token` from App Bridge
  2. `ManagedInstall` plug validates the token and builds a Shopifex session
  3. `put_shop_in_session/1` serializes the shop's **URL** (not the struct) into the LiveView session
  4. This hook reloads the shop from the session's `shop_url` server-side — no tokens needed

  Within a `live_session`, LiveView preserves the session across navigations.
  Full page loads get a fresh `id_token` from App Bridge automatically.

  ### Usage

      live_session :my_app,
        on_mount: [{ShopifexWeb.LiveSession, :embedded}],
        session: {ShopifexWeb.LiveSession, :put_shop_in_session, []}
  """
  def on_mount(:assign_shop_to_socket, _params, session, socket) do
    assigns = %{
      current_shop: load_shop(session["shop_url"]),
      session_token: session["session_token"]
    }

    {:cont, Phoenix.Component.assign(socket, assigns)}
  end

  @compile {:no_warn_undefined, Phoenix.LiveView}
  def on_mount(:embedded, _params, session, socket) do
    case load_shop(session["shop_url"]) do
      nil ->
        prefix = Application.get_env(:shopifex, :path_prefix, "")
        {:halt, Phoenix.LiveView.redirect(socket, to: "#{prefix}/auth")}

      shop ->
        {:cont, Phoenix.Component.assign(socket, current_shop: shop, session_token: nil)}
    end
  end

  # Reload the shop server-side from the URL stored in the session, so secrets
  # never reach the (signed-but-unencrypted) client session.
  defp load_shop(nil), do: nil
  defp load_shop(shop_url), do: Shopifex.Shops.get_shop_by_url(shop_url)
end
