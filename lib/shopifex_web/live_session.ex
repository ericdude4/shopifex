defmodule ShopifexWeb.LiveSession do
  # To avoid making LiveView a dependency of the entire application, we'll
  # silence this warning. At runtime, the LiveView module will be available
  # if the application is using LiveView.
  @compile {:no_warn_undefined, Phoenix.Component}

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
  """
  def put_shop_in_session(conn) do
    session_token = Shopifex.Plug.session_token(conn)
    current_shop = Shopifex.Plug.current_shop(conn)
    %{"session_token" => session_token, "current_shop" => current_shop}
  end

  @doc """
  Add the current_shop and session_token to assigns making them available
  in live view templates.
  """
  def on_mount(:assign_shop_to_socket, _params, session, socket) do
    assigns = %{
      current_shop: session["current_shop"],
      session_token: session["session_token"]
    }

    {:cont, Phoenix.Component.assign(socket, assigns)}
  end
end
