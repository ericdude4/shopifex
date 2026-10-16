defmodule Shopifex.ManagedInstall.Callbacks do
  @moduledoc """
  Extensibility hooks for the managed-installation flow
  (`Shopifex.Plug.ManagedInstall`).

  Managed installation runs inside a plug, *before* any controller, so it cannot
  use `ShopifexWeb.AuthController`'s `insert_shop/1` and `after_install/3`
  callbacks (those only apply to the legacy OAuth controller flow). Instead,
  configure a callback module here to customise how a newly token-exchanged shop
  is persisted and what side effects run on first install:

      config :shopifex,
        managed_install_callbacks: MyApp.ManagedInstallCallbacks

      defmodule MyApp.ManagedInstallCallbacks do
        use Shopifex.ManagedInstall.Callbacks

        @impl true
        def insert_shop(attrs) do
          # enforce single-tenant, attach defaults, etc.
          Shopifex.Shops.create_shop(attrs)
        end

        @impl true
        def after_install(shop) do
          # fetch shop profile, send yourself an email, take a baseline snapshot…
          :ok
        end
      end

  All callbacks are optional — `use Shopifex.ManagedInstall.Callbacks` provides
  defaults (`insert_shop/1` delegates to `Shopifex.Shops.create_shop/1`,
  `after_install/1` and `after_exchange/2` are no-ops). The plug always
  configures webhooks itself on first install. On re-exchange it reconciles
  webhooks too, but only when `config :shopifex, :configure_webhooks_on_exchange?`
  is not set to `false` (default `true`); either way, `:webhook_topics` set to
  `[]` disables registration entirely.

  ## When each hook runs

  | Hook                | First install | Token re-exchange (refresh) |
  |---------------------|:-------------:|:---------------------------:|
  | `insert_shop/1`     | ✅            | — (updates the row in place) |
  | `after_install/1`   | ✅            | —                           |
  | `after_exchange/2`  | ✅            | ✅                          |

  Use `after_exchange/2` for side effects that must run on refreshes too (it
  receives `new?`); use `after_install/1` for one-time install work.

  > **Callbacks run synchronously inside the plug**, in the merchant's request
  > and while the per-shop `Shopifex.TokenRefreshLease` is still held. Anything
  > slow (a profile fetch, snapshot, external sync) will block the page load —
  > spawn your own supervised `Task` for it. The library does not wrap
  > callbacks in a Task. Do not call `Shopifex.Auth.refresh/1` for the same
  > shop from a hook: it would wait out the lease deadline and return
  > `{:error, :refresh_in_progress}`.
  """

  @doc """
  Persist a brand-new shop from the token-exchange attributes and return the
  shop record. Defaults to `Shopifex.Shops.create_shop/1`.
  """
  @callback insert_shop(attrs :: map()) :: Shopifex.Plug.shop()

  @doc """
  Run app-specific side effects after a shop is installed for the first time
  (after persistence and webhook configuration). Defaults to a no-op.
  """
  @callback after_install(shop :: Shopifex.Plug.shop()) :: any()

  @doc """
  Run app-specific side effects after **every** successful token exchange — both
  first install (`new?` is `true`) and a refresh re-exchange (`new?` is `false`).
  Defaults to a no-op. Use this for work that must also happen on refreshes (e.g.
  re-sync external state), where `after_install/1` would only fire once.
  """
  @callback after_exchange(shop :: Shopifex.Plug.shop(), new? :: boolean()) :: any()

  @doc false
  def module do
    Application.get_env(:shopifex, :managed_install_callbacks, __MODULE__.Default)
  end

  defmacro __using__(_opts) do
    quote do
      @behaviour Shopifex.ManagedInstall.Callbacks

      @impl true
      def insert_shop(attrs), do: Shopifex.Shops.create_shop(attrs)

      @impl true
      def after_install(_shop), do: :ok

      @impl true
      def after_exchange(_shop, _new?), do: :ok

      defoverridable insert_shop: 1, after_install: 1, after_exchange: 2
    end
  end
end
