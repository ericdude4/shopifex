defmodule Shopifex.RedirectAfter.EctoTest do
  # The whole point of this implementation: state lives in the database, not in a
  # node-local Agent, so a value set on one node/process is recoverable on
  # another. These tests use the DB-backed store directly (DataCase gives a repo).
  use Shopifex.DataCase, async: false

  alias Shopifex.RedirectAfter.Ecto, as: Store

  test "round-trips the string charge id PaymentController produces from a GID" do
    # unwrap_charge/3 returns the trailing GID segment as a string ("4019552312"),
    # and Shopify's return-url charge_id also arrives as a string.
    assert :ok = Store.set("4019552312", "/back/here")
    assert Store.get("4019552312") == "/back/here"
  end

  test "set and get agree across binary/integer keys" do
    Store.set("777", "/x")
    assert Store.get(777) == "/x"

    Store.set(888, "/y")
    assert Store.get("888") == "/y"
  end

  test "get/1 consumes the entry (one-shot)" do
    Store.set("999", "/once")
    assert Store.get("999") == "/once"
    assert Store.get("999") == nil
  end

  test "get/1 returns nil for an unknown charge" do
    assert Store.get("123456789") == nil
  end

  test "a value set in one process is recovered in another (not process-local)" do
    Store.set("424242", "/cross/process")

    task = Task.async(fn -> Store.get("424242") end)

    assert Task.await(task) == "/cross/process"
  end

  test "set/2 upserts (last write wins) without raising on a duplicate charge" do
    Store.set("555", "/first")
    Store.set("555", "/second")
    assert Store.get("555") == "/second"
  end

  test "non-integer binary charge_id treated as miss without raising" do
    assert Store.get("not_an_int") == nil
    assert Store.set("not_an_int", "/foo") == :ok
    assert Store.get("not_an_int") == nil
  end
end
