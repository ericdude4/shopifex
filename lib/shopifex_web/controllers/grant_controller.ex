defmodule ShopifexWeb.GrantController do
  use ShopifexWeb, :controller

  alias Shopifex.Shops

  def grant_schema, do: Application.fetch_env!(:shopifex, :grant_schema)

  def index(conn, _params) do
    grants = Shops.list_grants()
    render(conn, "index.html", grants: grants)
  end

  def new(conn, _params) do
    changeset = Shops.change_grant(struct!(grant_schema()))
    render(conn, "new.html", changeset: changeset)
  end

  def create(conn, %{"grant" => grant_params}) do
    case Shops.create_grant(grant_params) do
      {:ok, grant} ->
        conn
        |> put_flash(:info, "Grant created successfully.")
        |> redirect(to: Routes.grant_path(conn, :show, grant))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    grant = Shops.get_grant!(id)
    render(conn, "show.html", grant: grant)
  end

  def edit(conn, %{"id" => id}) do
    grant = Shops.get_grant!(id)
    changeset = Shops.change_grant(grant)
    render(conn, "edit.html", grant: grant, changeset: changeset)
  end

  def update(conn, %{"id" => id, "grant" => grant_params}) do
    grant = Shops.get_grant!(id)

    case Shops.update_grant(grant, grant_params) do
      {:ok, grant} ->
        conn
        |> put_flash(:info, "Grant updated successfully.")
        |> redirect(to: Routes.grant_path(conn, :show, grant))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "edit.html", grant: grant, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    grant = Shops.get_grant!(id)
    {:ok, _grant} = Shops.delete_grant(grant)

    conn
    |> put_flash(:info, "Grant deleted successfully.")
    |> redirect(to: Routes.grant_path(conn, :index))
  end
end
