defmodule ShopifexWeb.AuthErrorHandler do
  import Phoenix.Controller, only: [json: 2]
  import Plug.Conn, only: [put_status: 2]
  alias Plug.Conn.Status

  def auth_error(conn, {_type, _reason}, _opts) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "unauthorized", status: Status.code(:unauthorized)})
  end
end
