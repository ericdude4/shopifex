defmodule Shopifex.Plug.FetchFlashTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest
  import Plug.Conn, only: [get_session: 2]

  alias Shopifex.Plug.FetchFlash

  test "put_flash works after calling FetchFlash" do
    conn =
      build_conn()
      |> init_test_session(%{})
      |> FetchFlash.call([])
      |> Phoenix.Controller.put_flash(:info, "flash message")

    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "flash message"
  end

  test "flash set before redirect survives into session" do
    conn =
      build_conn()
      |> init_test_session(%{})
      |> FetchFlash.call([])
      |> Phoenix.Controller.put_flash(:info, "persisted message")
      |> Phoenix.Controller.redirect(to: "/somewhere")

    # The before_send callback in Phoenix's fetch_flash wrote the flash to the session
    assert get_session(conn, "phoenix_flash") == %{"info" => "persisted message"}
  end

  test "calling FetchFlash after Phoenix's fetch_flash is harmless and idempotent" do
    conn =
      build_conn()
      |> init_test_session(%{})
      |> Phoenix.Controller.fetch_flash([])
      |> FetchFlash.call([])
      |> Phoenix.Controller.put_flash(:error, "error message")

    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "error message"
  end
end
