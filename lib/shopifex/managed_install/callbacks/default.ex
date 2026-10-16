defmodule Shopifex.ManagedInstall.Callbacks.Default do
  @moduledoc """
  Default managed-install callbacks: persist a new shop via
  `Shopifex.Shops.create_shop/1` and run no extra side effects on install.

  Override by configuring your own module:

      config :shopifex, managed_install_callbacks: MyApp.ManagedInstallCallbacks
  """
  use Shopifex.ManagedInstall.Callbacks
end
