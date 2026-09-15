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

      def get_url_field() do
        # TODO: dont check for defaults in v3.0
        if Keyword.has_key?(shop_schema().__info__(:functions), :shopifex_url_field) do
          shop_schema().shopifex_url_field()
        else
          :url
        end
      end

      def get_scope_field() do
        # TODO: dont check for defaults in v3.0
        if Keyword.has_key?(shop_schema().__info__(:functions), :shopifex_scope_field) do
          shop_schema().shopifex_scope_field()
        else
          :scope
        end
      end

      defp get_filters() do
        # TODO: dont check for defaults in v3.0
        if Keyword.has_key?(shop_schema().__info__(:functions), :shopifex_filters) do
          shop_schema().shopifex_filters()
        else
          []
        end
      end

      defp get_preloads() do
        # TODO: dont check for defaults in v3.0
        if Keyword.has_key?(shop_schema().__info__(:functions), :shopifex_preloads) do
          shop_schema().shopifex_preloads()
        else
          []
        end
      end

      defp schema_field(function, default) do
        if Keyword.has_key?(shop_schema().__info__(:functions), function) do
          apply(shop_schema(), function, [])
        else
          default
        end
      end

      def get_refresh_token_field(),
        do: schema_field(:shopifex_refresh_token_field, :refresh_token)

      def get_access_token_expires_at_field(),
        do: schema_field(:shopifex_access_token_expires_at_field, :access_token_expires_at)

      def get_refresh_token_expires_at_field(),
        do: schema_field(:shopifex_refresh_token_expires_at_field, :refresh_token_expires_at)

      @doc """
      Reloads the shop from the database, bypassing any caching layer in front of
      `get_shop_by_url/1`. Used before refreshing an access token so that a refresh
      performed by another process is picked up instead of repeated.
      """
      def reload_shop(shop) do
        shop_schema()
        |> repo().get_by!(Ecto.primary_key(shop))
        |> repo().preload(get_preloads())
      end

      @doc """
      Returns the stored refresh token for the shop, or `nil` when the shop was
      installed with a non-expiring offline access token.
      """
      def get_refresh_token(shop), do: Map.get(shop, get_refresh_token_field())

      def get_access_token_expires_at(shop),
        do: Map.get(shop, get_access_token_expires_at_field())

      def get_refresh_token_expires_at(shop),
        do: Map.get(shop, get_refresh_token_expires_at_field())

      @doc """
      Whether the shop holds an *expiring* offline access token (i.e. one that
      was issued with a refresh token).
      """
      def expiring_access_token?(shop), do: not is_nil(get_access_token_expires_at(shop))

      @doc """
      Whether the shop's refresh token is missing or has passed its 90 day expiry.
      Such shops must go through OAuth again before they can make API calls.
      """
      def refresh_token_expired?(shop, now \\ DateTime.utc_now()) do
        case {get_refresh_token(shop), get_refresh_token_expires_at(shop)} do
          {nil, _} -> true
          {_, nil} -> false
          {_, expires_at} -> DateTime.compare(now, expires_at) != :lt
        end
      end

      @doc """
      Whether the access token is expired, or will expire within `margin` seconds
      (defaults to `config :shopifex, access_token_refresh_margin`).
      Non-expiring tokens never expire.
      """
      def access_token_expiring?(
            shop,
            margin \\ Shopifex.OAuth.access_token_refresh_margin(),
            now \\ DateTime.utc_now()
          ) do
        case get_access_token_expires_at(shop) do
          nil -> false
          expires_at -> DateTime.compare(DateTime.add(now, margin, :second), expires_at) != :lt
        end
      end

      def access_token_expired?(shop, now \\ DateTime.utc_now()),
        do: access_token_expiring?(shop, 0, now)

      @doc """
      Returns `{:ok, shop}` with a usable access token, refreshing the expiring
      offline access token first when it is expired or about to expire.

      Returns `{:error, reason}` when a refresh was required but failed. When the
      refresh token was rejected by Shopify (`:invalid_grant`) it is cleared from
      the shop so that `Shopifex.Plug.EnsureAccessToken` sends the merchant back
      through OAuth the next time they open the app.
      """
      def ensure_fresh_access_token(shop) do
        if access_token_expiring?(shop) do
          refresh_access_token(shop)
        else
          {:ok, shop}
        end
      end

      @doc """
      Returns `{:ok, access_token}` for the shop, refreshing it first if needed.
      See `ensure_fresh_access_token/1`.
      """
      def get_access_token(shop) do
        with {:ok, shop} <- ensure_fresh_access_token(shop) do
          {:ok, shop.access_token}
        end
      end

      @doc """
      Same as `get_access_token/1` but raises `Shopifex.AccessTokenError` when
      no usable token can be obtained.
      """
      def get_access_token!(shop) do
        case get_access_token(shop) do
          {:ok, access_token} ->
            access_token

          {:error, reason} ->
            raise Shopifex.AccessTokenError, shop_url: get_url(shop), reason: reason
        end
      end

      @doc """
      Refreshes the shop's expiring offline access token and persists the new
      access token / refresh token pair atomically.

      Refreshes are serialized per shop through `with_access_token_refresh_lock/2`.
      Inside the lock the shop is reloaded from the database: if another process
      already rotated the token (the stored access token differs from the one we
      hold) the reloaded shop is returned without calling Shopify again.

      Returns `{:ok, shop}` or `{:error, reason}`.
      """
      def refresh_access_token(shop) do
        with_access_token_refresh_lock(shop, fn ->
          reloaded = reload_shop(shop)

          cond do
            reloaded.access_token != shop.access_token and not access_token_expiring?(reloaded) ->
              Logger.info("Access token for #{get_url(shop)} was already refreshed elsewhere")
              {:ok, reloaded}

            refresh_token_expired?(reloaded) ->
              {:error, :refresh_token_expired}

            true ->
              do_refresh_access_token(reloaded)
          end
        end)
      end

      defp do_refresh_access_token(shop) do
        shop_url = get_url(shop)

        case Shopifex.OAuth.refresh_access_token(shop_url, get_refresh_token(shop)) do
          {:ok, params} ->
            Logger.info("Refreshed expiring offline access token for #{shop_url}")
            {:ok, update_shop(shop, token_params_to_shop_params(params))}

          {:error, :invalid_grant, details} ->
            Logger.error(
              "Refresh token for #{shop_url} was rejected by Shopify, the shop must re-authorize: #{inspect(details)}"
            )

            # Clear the refresh token so the shop is sent through OAuth again on
            # the next app load, and background jobs fail fast instead of
            # hammering Shopify with a dead refresh token.
            update_shop(shop, %{get_refresh_token_field() => nil})
            {:error, :invalid_grant}

          {:error, reason, _details} ->
            {:error, reason}
        end
      end

      @doc """
      Maps the normalized `Shopifex.OAuth.token_params/1` onto the configured shop
      schema fields.
      """
      def token_params_to_shop_params(params) do
        shop_params = %{
          :access_token => params.access_token,
          get_refresh_token_field() => params[:refresh_token],
          get_access_token_expires_at_field() => params[:access_token_expires_at],
          get_refresh_token_expires_at_field() => params[:refresh_token_expires_at]
        }

        case params[:scope] do
          nil -> shop_params
          scope -> Map.put(shop_params, get_scope_field(), scope)
        end
      end

      @doc """
      Serializes access token refreshes for a shop. The default implementation
      takes a cluster-wide `:global` lock keyed on the shop URL, which is
      sufficient for BEAM clusters. Override this in your shops context to use a
      different lock (for example Redis) when your nodes are not clustered.
      """
      def with_access_token_refresh_lock(shop, fun) do
        lock_id = {{Shopifex, :access_token_refresh, get_url(shop)}, self()}

        case :global.trans(lock_id, fun, [node() | Node.list()], :infinity) do
          :aborted -> {:error, :refresh_lock_aborted}
          result -> result
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
      Check the webhooks set on the shop, then compare that to the required webhooks based on the current
      status of the shop.

      Returns a list of webhooks which were created.
      """
      def configure_webhooks(shop) do
        with {:ok, current_webhooks} <- get_current_webhooks(shop) do
          current_webhook_topics = Enum.map(current_webhooks, & &1.topic)

          Logger.info(
            "All current webhook topics for #{get_url(shop)}: #{Enum.join(current_webhook_topics, ", ")}"
          )

          current_webhook_topics = MapSet.new(current_webhook_topics)

          topics = MapSet.new(Application.fetch_env!(:shopifex, :webhook_topics))

          # Make sure all the required topics are configured.
          subscribe_to_topics = MapSet.difference(topics, current_webhook_topics)

          Enum.reduce(subscribe_to_topics, [], fn topic, acc ->
            Logger.info("Subscribing to topic #{topic}")

            case create_webhook(shop, topic) do
              {:ok, webhook} ->
                [webhook | acc]

              error ->
                Logger.info("Error subscribing to topic #{topic}: \n#{inspect(error)}")
                acc
            end
          end)
        end
      end

      @doc """
      Returns the current webhooks for a Shop from the Shopify API.

      Returns with `{:ok, webhooks}` on success. Can also return any
      non-200 level HTTPoison response, or a Jason decode error.
      """
      @spec get_current_webhooks(shop :: shop()) :: {:ok, list()} | any()
      def get_current_webhooks(shop) do
        with {:ok, access_token} <- get_access_token(shop),
             {:ok, %HTTPoison.Response{status_code: 200, body: body}} <-
               HTTPoison.get(
                 "https://#{get_url(shop)}/admin/api/2026-01/webhooks.json",
                 "X-Shopify-Access-Token": access_token,
                 "Content-Type": "application/json"
               ),
             {:ok, %{webhooks: webhooks}} <- Jason.decode(body, keys: :atoms) do
          {:ok, webhooks}
        end
      end

      defp create_webhook(shop, topic) do
        with {:ok, access_token} <- get_access_token(shop),
             {:ok, %HTTPoison.Response{status_code: 201, body: body}} <-
               HTTPoison.post(
                 "https://#{get_url(shop)}/admin/api/2026-01/webhooks.json",
                 Jason.encode!(%{
                   webhook: %{
                     topic: topic,
                     address: "#{Application.get_env(:shopifex, :webhook_uri)}",
                     format: "json"
                   }
                 }),
                 "X-Shopify-Access-Token": access_token,
                 "Content-Type": "application/json"
               ),
             {:ok, %{webhook: webhook}} <- Jason.decode(body, keys: :atoms) do
          {:ok, webhook}
        end
      end

      def delete_webhook(shop, id) do
        with {:ok, access_token} <- get_access_token(shop) do
          HTTPoison.delete(
            "https://#{get_url(shop)}/admin/api/2026-01/webhooks/#{id}.json",
            "X-Shopify-Access-Token": access_token,
            "Content-Type": "application/json"
          )
        end
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
                     get_url_field: 0,
                     get_refresh_token_field: 0,
                     get_access_token_expires_at_field: 0,
                     get_refresh_token_expires_at_field: 0,
                     reload_shop: 1,
                     get_refresh_token: 1,
                     get_access_token_expires_at: 1,
                     get_refresh_token_expires_at: 1,
                     expiring_access_token?: 1,
                     refresh_token_expired?: 1,
                     refresh_token_expired?: 2,
                     access_token_expiring?: 1,
                     access_token_expiring?: 2,
                     access_token_expiring?: 3,
                     access_token_expired?: 1,
                     access_token_expired?: 2,
                     ensure_fresh_access_token: 1,
                     get_access_token: 1,
                     get_access_token!: 1,
                     refresh_access_token: 1,
                     token_params_to_shop_params: 1,
                     with_access_token_refresh_lock: 2,
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
