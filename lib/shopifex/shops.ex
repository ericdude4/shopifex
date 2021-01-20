defmodule Shopifex.Shops do
  import Ecto.Query, warn: false
  require Logger

  @moduledoc """
  This module acts as the context for any database interaction from within the Shopifex
  package.
  """

  def shop_schema, do: Application.fetch_env!(:shopifex, :shop_schema)
  def grant_schema, do: Application.fetch_env!(:shopifex, :grant_schema)
  def plan_schema, do: Application.fetch_env!(:shopifex, :plan_schema)
  def repo, do: Application.fetch_env!(:shopifex, :repo)

  def get_shop_by_url(url) do
    from(s in shop_schema(),
      where: s.url == ^url
    )
    |> repo().one()
  end

  def create_shop(params) do
    shop_schema().changeset(struct!(shop_schema()), params)
    |> repo().insert!()
  end

  def update_shop(shop, params) do
    shop_schema().changeset(shop, params)
    |> repo().update!()
  end

  def delete_shop(shop) do
    repo().delete!(shop)
  end

  def create_shop_grant(shop, grants) do
    grant_schema().changeset(struct!(grant_schema()), %{shop: shop, grants: grants})
    |> repo().insert!()
  end

  @doc """
  Check the webhooks set on the shop, then compare that to the required webhooks based on the current
  status of the shop.
  """
  def configure_webhooks(shop) do
    {:ok, webhooks_response} =
      Shopify.session(shop.url, shop.access_token)
      |> Shopify.Webhook.all()

    webhooks = webhooks_response.data

    current_webhook_topics =
      webhooks
      |> Enum.map(& &1.topic)

    Logger.info(
      "All current webhook topics for #{shop.url}: #{Enum.join(current_webhook_topics, ", ")}"
    )

    current_webhook_topics = MapSet.new(current_webhook_topics)

    topics = MapSet.new(Application.fetch_env!(:shopifex, :webhook_topics))

    # Make sure all the required topics are conifgured.
    subscribe_to_topics = MapSet.difference(topics, current_webhook_topics)

    Enum.each(subscribe_to_topics, fn topic ->
      Logger.info("subscribing to topic #{topic}")
      create_webhook(shop, topic)
    end)
  end

  defp create_webhook(shop, topic) do
    {:ok, _response} =
      HTTPoison.post(
        "https://#{shop.url}/admin/webhooks.json",
        Jason.encode!(%{
          webhook: %{
            topic: topic,
            address: "#{Application.get_env(:shopifex, :webhook_uri)}",
            format: "json"
          }
        }),
        "X-Shopify-Access-Token": shop.access_token,
        "Content-Type": "application/json"
      )
  end

  @doc """
  Returns the list of plans.

  ## Examples

      iex> list_plans()
      [%Plan{}, ...]

  """
  def list_plans do
    repo().all(plan_schema())
  end

  @doc """
  Returns the list of plans.

  ## Examples

      iex> list_plans()
      [%Plan{}, ...]

  """

  def list_plans_granting_guard(guard) do
    from(p in plan_schema(),
      where: ^guard in p.grants
    )
    |> repo().all()
  end

  @doc """
  Gets a single plan.

  Raises `Ecto.NoResultsError` if the Plan does not exist.

  ## Examples

      iex> get_plan!(123)
      %Plan{}

      iex> get_plan!(456)
      ** (Ecto.NoResultsError)

  """
  def get_plan!(id), do: repo().get!(plan_schema(), id)

  @doc """
  Creates a plan.

  ## Examples

      iex> create_plan(%{field: value})
      {:ok, %Plan{}}

      iex> create_plan(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_plan(attrs \\ %{}) do
    struct!(plan_schema())
    |> plan_schema().changeset(attrs)
    |> repo().insert()
  end

  @doc """
  Updates a plan.

  ## Examples

      iex> update_plan(plan, %{field: new_value})
      {:ok, %Plan{}}

      iex> update_plan(plan, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_plan(plan, attrs) do
    plan
    |> plan_schema().changeset(attrs)
    |> repo().update()
  end

  @doc """
  Deletes a plan.

  ## Examples

      iex> delete_plan(plan)
      {:ok, %Plan{}}

      iex> delete_plan(plan)
      {:error, %Ecto.Changeset{}}

  """
  def delete_plan(plan) do
    repo().delete(plan)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking plan changes.

  ## Examples

      iex> change_plan(plan)
      %Ecto.Changeset{data: %Plan{}}

  """
  def change_plan(plan, attrs \\ %{}) do
    plan_schema().changeset(plan, attrs)
  end

  @doc """
  Returns the list of grants.

  ## Examples

      iex> list_grants()
      [%Grant{}, ...]

  """
  def list_grants do
    repo().all(grant_schema())
  end

  @doc """
  Gets a single grant.

  Raises `Ecto.NoResultsError` if the Grant does not exist.

  ## Examples

      iex> get_grant!(123)
      %Grant{}

      iex> get_grant!(456)
      ** (Ecto.NoResultsError)

  """
  def get_grant!(id), do: repo().get!(grant_schema(), id)

  @doc """
  Creates a grant.

  ## Examples

      iex> create_grant(%{field: value})
      {:ok, %Grant{}}

      iex> create_grant(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_grant(attrs \\ %{}) do
    struct!(grant_schema())
    |> grant_schema().changeset(attrs)
    |> repo().insert()
  end

  @doc """
  Updates a grant.

  ## Examples

      iex> update_grant(grant, %{field: new_value})
      {:ok, %Grant{}}

      iex> update_grant(grant, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_grant(grant, attrs) do
    grant
    |> grant_schema().changeset(attrs)
    |> repo().update()
  end

  @doc """
  Deletes a grant.

  ## Examples

      iex> delete_grant(grant)
      {:ok, %Grant{}}

      iex> delete_grant(grant)
      {:error, %Ecto.Changeset{}}

  """
  def delete_grant(grant) do
    repo().delete(grant)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking grant changes.

  ## Examples

      iex> change_grant(grant)
      %Ecto.Changeset{data: %Grant{}}

  """
  def change_grant(grant, attrs \\ %{}) do
    grant_schema().changeset(grant, attrs)
  end
end
