defmodule Shopifex.Shops do
  @moduledoc """
  The Shops context. This module calls the default Shopifex.ShopsContextClient, which in turn calls the functions defined in the ShopsContext behaviour.
  You can swap out the default client for your own implementation by setting the :shops_context_client config value for the :shopifex app to a module that uses Shopifex.ShopsContext
  and overrides various functions.
  """
  def shop_schema(), do: client().shop_schema()
  def grant_schema(), do: client().grant_schema()
  def plan_schema(), do: client().plan_schema()
  def repo(), do: client().repo()
  def get_shop_by_url(url), do: client().get_shop_by_url(url)
  def get_url(shop), do: client().get_url(shop)
  def get_scope(shop), do: client().get_scope(shop)
  def get_scope_field(), do: client().get_scope_field()
  def create_shop(params), do: client().create_shop(params)
  def update_shop(shop, params), do: client().update_shop(shop, params)
  def delete_shop(shop), do: client().delete_shop(shop)
  def create_shop_grant(shop, grants), do: client().create_shop_grant(shop, grants)
  def configure_webhooks(shop), do: client().configure_webhooks(shop)
  def get_current_webhooks(shop), do: client().get_current_webhooks(shop)
  def delete_webhook(shop, id), do: client().delete_webhook(shop, id)
  def list_plans(), do: client().list_plans()
  def list_plans_granting_guard(guard), do: client().list_plans_granting_guard(guard)
  def get_plan!(id), do: client().get_plan!(id)
  def create_plan(), do: client().create_plan()
  def create_plan(attrs), do: client().create_plan(attrs)
  def update_plan(plan, attrs), do: client().update_plan(plan, attrs)
  def delete_plan(plan), do: client().delete_plan(plan)
  def change_plan(plan), do: client().change_plan(plan)
  def change_plan(plan, attrs), do: client().change_plan(plan, attrs)
  def list_grants(), do: client().list_grants()
  def get_grant!(id), do: client().get_grant!(id)
  def create_grant(), do: client().create_grant()
  def create_grant(attrs), do: client().create_grant(attrs)
  def update_grant(grant, attrs), do: client().update_grant(grant, attrs)
  def delete_grant(grant), do: client().delete_grant(grant)
  def change_grant(grant), do: client().change_grant(grant)
  def change_grant(grant, attrs), do: client().change_grant(grant, attrs)

  defp client(),
    do: Application.get_env(:shopifex, :shops_context_client, Shopifex.ShopsContextClient)
end
