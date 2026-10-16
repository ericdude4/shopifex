defmodule ShopifexWeb.LiveSessionTest do
  use ShopifexWeb.ConnCase, async: false

  alias ShopifexWeb.LiveSession

  setup [:shop_in_session]

  test "put_shop_in_session/1 serializes only the shop URL, never the access/refresh token", %{
    conn: conn,
    shop: shop
  } do
    session = LiveSession.put_shop_in_session(conn)

    assert session["shop_url"] == shop.url
    refute Map.has_key?(session, "current_shop")

    # The LV session is signed but not encrypted (readable client-side) — secrets must not be in it.
    refute inspect(session) =~ shop.access_token
  end

  test "on_mount(:assign_shop_to_socket) reloads the shop from the URL", %{shop: shop} do
    {:cont, socket} =
      LiveSession.on_mount(
        :assign_shop_to_socket,
        %{},
        %{"shop_url" => shop.url, "session_token" => "tok"},
        %Phoenix.LiveView.Socket{}
      )

    assert socket.assigns.current_shop.url == shop.url
    assert socket.assigns.session_token == "tok"
  end

  test "on_mount(:embedded) redirects to /auth when no shop is in the session" do
    assert {:halt, socket} =
             LiveSession.on_mount(
               :embedded,
               %{},
               %{"shop_url" => nil},
               %Phoenix.LiveView.Socket{}
             )

    assert {:redirect, %{to: "/auth"}} = socket.redirected
  end

  test "on_mount(:embedded) redirects respecting path_prefix" do
    Application.put_env(:shopifex, :path_prefix, "/my_prefix")
    on_exit(fn -> Application.delete_env(:shopifex, :path_prefix) end)

    assert {:halt, socket} =
             LiveSession.on_mount(
               :embedded,
               %{},
               %{"shop_url" => nil},
               %Phoenix.LiveView.Socket{}
             )

    assert {:redirect, %{to: "/my_prefix/auth"}} = socket.redirected
  end
end
