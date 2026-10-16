defmodule Shopifex.ShopsContext do
  defmacro __using__(_opts) do
    quote do
      import Ecto.Query, warn: false
      require Logger

      @type shop :: %{access_token: String.t(), scope: String.t(), url: String.t()}

      def shop_schema, do: Application.fetch_env!(:shopifex, :shop_schema)
      def grant_schema, do: Application.fetch_env!(:shopifex, :grant_schema)
      def plan_schema, do: Application.fetch_env!(:shopifex, :plan_schema)
      def repo, do: Application.fetch_env!(:shopifex, :repo)

      def get_shop_by_url(url) do
        url_field = get_url_field()

        filters = get_filters()
        preloads = get_preloads()

        shop_schema()
        |> where(^[{url_field, url}])
        |> add_additional_filters(filters)
        |> preload(^preloads)
        |> repo().one()
      end

      def get_url(shop) do
        Map.get(shop, get_url_field())
      end

      def get_scope(shop) do
        Map.get(shop, get_scope_field())
      end

      defp get_url_field(), do: shopifex_schema_opt(:shopifex_url_field, :url)

      def get_scope_field(), do: shopifex_schema_opt(:shopifex_scope_field, :scope)

      defp get_filters(), do: shopifex_schema_opt(:shopifex_filters, [])

      defp get_preloads(), do: shopifex_schema_opt(:shopifex_preloads, [])

      # A shop schema can use the default field names (`:url`/`:scope`, what
      # `mix shopifex.install` generates) or opt into custom names/filters/preloads
      # via `use Shopifex.Shop`, which injects `shopifex_*_field/0` accessors. Both
      # are supported: use the accessor when the schema defines it, otherwise fall
      # back to the documented default. `Code.ensure_loaded?/1` keeps this correct
      # even if the schema module hasn't been loaded yet.
      defp shopifex_schema_opt(fun, default) do
        schema = shop_schema()

        if Code.ensure_loaded?(schema) and function_exported?(schema, fun, 0) do
          apply(schema, fun, [])
        else
          default
        end
      end

      defp add_additional_filters(query, filter_keys) do
        Enum.reduce(filter_keys, query, fn
          {key, nil}, acc ->
            from(x in acc, where: is_nil(field(x, ^key)))

          {key, [in: values]}, acc ->
            from(x in acc, where: field(x, ^key) in ^values)

          {key, value}, acc ->
            where(acc, ^[{key, value}])
        end)
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
      Ensures the shop is subscribed to every topic in
      `config :shopifex, :webhook_topics`, creating any that are missing via the
      GraphQL `webhookSubscriptionCreate` mutation.

      Returns a list of the webhooks which were created (with app-facing
      REST-style topic strings, e.g. `"orders/create"`).
      """
      def configure_webhooks(shop) do
        case Application.fetch_env!(:shopifex, :webhook_topics) do
          [] ->
            # Nothing desired: skip the GraphQL round-trip entirely rather
            # than fetching current subscriptions just to reconcile against
            # an empty set.
            []

          desired_topics ->
            with {:ok, current_webhooks} <- get_current_webhooks(shop) do
              current_topics = current_webhooks |> Enum.map(& &1.topic) |> MapSet.new()

              Logger.info(
                "All current webhook topics for #{get_url(shop)}: #{Enum.join(MapSet.to_list(current_topics), ", ")}"
              )

              Enum.reduce(desired_topics, [], fn topic, acc ->
                if MapSet.member?(current_topics, webhook_topic_to_graphql(topic)) do
                  acc
                else
                  Logger.info("Subscribing to topic #{topic}")

                  case create_webhook(shop, topic) do
                    {:ok, webhook} ->
                      [webhook | acc]

                    error ->
                      Logger.info("Error subscribing to topic #{topic}: \n#{inspect(error)}")
                      acc
                  end
                end
              end)
            end
        end
      end

      @doc """
      Returns the shop's current webhook subscriptions via the GraphQL
      `webhookSubscriptions` query.

      Topics come back as Shopify GraphQL enum values (e.g. `"ORDERS_CREATE"`),
      which is the authoritative form `configure_webhooks/1` compares against.

      Returns `{:ok, webhooks}` on success.
      """
      @spec get_current_webhooks(shop :: shop()) :: {:ok, list()} | any()
      def get_current_webhooks(shop) do
        # 250 is Shopify's maximum page size. Shopifex registers one
        # subscription per configured topic and this list is per app and per
        # shop, so a single page covers every supported configuration; the
        # query is not paginated.
        query = """
        query {
          webhookSubscriptions(first: 250) {
            edges {
              node {
                id
                topic
              }
            }
          }
        }
        """

        case Shopifex.API.graphql(shop, query) do
          {:ok, %{"webhookSubscriptions" => %{"edges" => edges}}} ->
            {:ok,
             Enum.map(edges, fn %{"node" => %{"id" => id, "topic" => topic}} ->
               %{id: id, topic: topic}
             end)}

          other ->
            other
        end
      end

      defp create_webhook(shop, topic) do
        mutation = """
        mutation webhookSubscriptionCreate($topic: WebhookSubscriptionTopic!, $webhookSubscription: WebhookSubscriptionInput!) {
          webhookSubscriptionCreate(topic: $topic, webhookSubscription: $webhookSubscription) {
            webhookSubscription {
              id
            }
            userErrors {
              field
              message
            }
          }
        }
        """

        variables = %{
          topic: webhook_topic_to_graphql(topic),
          webhookSubscription: %{
            callbackUrl: Application.get_env(:shopifex, :webhook_uri),
            format: "JSON"
          }
        }

        case Shopifex.API.graphql(shop, mutation, variables) do
          {:ok,
           %{
             "webhookSubscriptionCreate" => %{
               "userErrors" => [],
               "webhookSubscription" => %{"id" => id}
             }
           }} ->
            {:ok, %{id: id, topic: topic}}

          {:ok, %{"webhookSubscriptionCreate" => %{"userErrors" => errors}}} ->
            {:error, errors}

          other ->
            other
        end
      end

      @doc """
      Deletes a webhook subscription by its GraphQL ID via
      `webhookSubscriptionDelete`.
      """
      def delete_webhook(shop, id) do
        mutation = """
        mutation webhookSubscriptionDelete($id: ID!) {
          webhookSubscriptionDelete(id: $id) {
            deletedWebhookSubscriptionId
            userErrors {
              field
              message
            }
          }
        }
        """

        case Shopifex.API.graphql(shop, mutation, %{id: id}) do
          {:ok,
           %{
             "webhookSubscriptionDelete" => %{
               "userErrors" => [],
               "deletedWebhookSubscriptionId" => deleted_id
             }
           }} ->
            {:ok, deleted_id}

          {:ok, %{"webhookSubscriptionDelete" => %{"userErrors" => errors}}} ->
            {:error, errors}

          other ->
            other
        end
      end

      # Shopify GraphQL webhook topics are uppercase enums with "/" and "."
      # replaced by "_" (e.g. "orders/create" -> "ORDERS_CREATE",
      # "customers/data_request" -> "CUSTOMERS_DATA_REQUEST").
      defp webhook_topic_to_graphql(topic) do
        topic |> String.replace(["/", "."], "_") |> String.upcase()
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
      Returns the list of plans granting a specific guard.

      ## Examples

          iex> list_plans_granting_guard(:some_guard)
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

      defoverridable shop_schema: 0,
                     grant_schema: 0,
                     plan_schema: 0,
                     repo: 0,
                     get_shop_by_url: 1,
                     get_url: 1,
                     get_scope: 1,
                     get_scope_field: 0,
                     create_shop: 1,
                     update_shop: 2,
                     delete_shop: 1,
                     create_shop_grant: 2,
                     configure_webhooks: 1,
                     get_current_webhooks: 1,
                     delete_webhook: 2,
                     list_plans: 0,
                     list_plans_granting_guard: 1,
                     get_plan!: 1,
                     create_plan: 0,
                     create_plan: 1,
                     update_plan: 2,
                     delete_plan: 1,
                     change_plan: 1,
                     change_plan: 2,
                     list_grants: 0,
                     get_grant!: 1,
                     create_grant: 0,
                     create_grant: 1,
                     update_grant: 2,
                     delete_grant: 1,
                     change_grant: 1,
                     change_grant: 2
    end
  end
end
