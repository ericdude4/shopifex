defmodule Shopifex.RedirectAfterAgent do
  use Agent
  require Logger

  def start_link(_) do
    Logger.info("Starting redirect_uri agent")
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def get(charge_id) do
    Logger.info("Getting redirect_uri for charge #{charge_id}")
    redirect_uri = Agent.get(__MODULE__, &Map.get(&1, charge_id))
    Logger.info("Clearing redirect_uri for charge #{charge_id}")
    Agent.update(__MODULE__, &Map.delete(&1, charge_id))
    redirect_uri
  end

  def set(charge_id, redirect_uri) do
    Logger.info("Storing redirect_uri for charge #{charge_id}")
    Agent.update(__MODULE__, &Map.put(&1, charge_id, redirect_uri))
  end
end
