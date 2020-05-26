defmodule ShopifexWeb.Router do
  @moduledoc """
  Use this module in your normal router. This adds a number of convenience methods for you to
  use in your pipelines.

  Examples:

  `:shopify_webhook` validates all incoming webhooks
  ```elixir
  scope "/webhook", MyAppWeb do
    pipe_through [:shopify_webhook]

    post "/", WebhookController, :action
  end
  ```

  `:browser` removes the x-frame-options header and keeps the current session active. `:shopify_session` ensures that a valid store is currently loaded in the session and is accessible in your controllers/templates as `conn.private.shop`
  ```elixir
  scope "/", MyAppWeb do
    pipe_through [:browser, :shopify_session]

    get "/", PageController, :index
  end
  ```
  """
  defmacro __using__(_opts) do
    with {:ok, shop_schema} <- Application.fetch_env(:shopifex, :shop_schema),
         {:ok, repo} <- Application.fetch_env(:shopifex, :repo),
         {:ok, secret} <- Application.fetch_env(:shopifex, :secret) do
      quote do
        use ShopifexWeb, :router
        import Ecto.Query, warn: false

        pipeline :browser do
          plug :accepts, ["html"]
          plug :fetch_session
          plug :custom_fetch_flash
          plug :protect_from_forgery
          plug :put_secure_browser_headers
          plug :delete_x_frame_options_header
        end

        pipeline :api do
          plug :accepts, ["json"]
          plug :delete_x_frame_options_header
        end

        pipeline :shopify_session do
          plug :verify_shop_in_session
        end

        pipeline :shopify_webhook do
          plug :validate_webhook_hmac
        end

        scope "/auth", ShopifexWeb do
          pipe_through(:browser)
          get "/", AuthController, :auth
          get "/install", AuthController, :install
        end

        def verify_shop_in_session(conn, _) do
          case Phoenix.Controller.get_flash(conn, :shop) do
            %{__struct__: unquote(shop_schema)} = shop ->
              conn

            _ ->
              conn
              |> redirect(to: "/auth")
              |> halt()
          end
        end

        def validate_webhook_hmac(conn, _) do
          {header_hmac, our_hmac} =
            case conn.method do
              "GET" ->
                query_string =
                  Regex.named_captures(~r/(?:hmac=[^&]*)&(?'query_string'.*)/, conn.query_string)[
                    "query_string"
                  ]

                {
                  conn.params["hmac"],
                  :crypto.hmac(
                    :sha256,
                    unquote(secret),
                    query_string
                  )
                  |> Base.encode16()
                  |> String.downcase()
                }

              "POST" ->
                case Plug.Conn.get_req_header(conn, "x-shopify-hmac-sha256") do
                  [header_hmac] ->
                    our_hmac =
                      :crypto.hmac(
                        :sha256,
                        unquote(secret),
                        conn.assigns[:raw_body]
                      )
                      |> Base.encode64()

                    {header_hmac, our_hmac}

                  [] ->
                    conn
                    |> send_resp(401, "missing hmac signature")
                    |> halt()
                end
            end

          if our_hmac == header_hmac do
            conn
          else
            conn
            |> send_resp(401, "invalid hmac signature")
            |> halt()
          end
        end

        @doc """
        This allows your application to load inside of an iframe
        """
        def delete_x_frame_options_header(conn, _) do
          Plug.Conn.delete_resp_header(conn, "x-frame-options")
        end

        @doc """
        This maintains the Shopify sesson as the user navigates around your application
        """
        def custom_fetch_flash(conn, _opts \\ []) do
          session_flash = Plug.Conn.get_session(conn, "phoenix_flash")
          conn = Plug.Conn.put_private(conn, :phoenix_flash, session_flash || %{})

          register_before_send(conn, fn conn ->
            flash = conn.private.phoenix_flash
            flash_size = map_size(flash)

            cond do
              is_nil(session_flash) and flash_size == 0 ->
                conn

              flash_size > 0 and conn.status in 300..308 ->
                Plug.Conn.put_session(conn, "phoenix_flash", flash)

              flash_size > 0 and conn.status in 200..299 ->
                flash = Map.take(flash, ["shop_url", "shop"])
                Plug.Conn.put_session(conn, "phoenix_flash", flash)

              true ->
                Plug.Conn.delete_session(conn, "phoenix_flash")
            end
          end)
        end
      end
    else
      _ ->
        raise(ShopifexError, "Make sure to configure all required :shopifex config options")
    end
  end
end
