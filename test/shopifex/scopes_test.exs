defmodule Shopifex.ScopesTest do
  use ExUnit.Case, async: true

  alias Shopifex.Scopes

  doctest Shopifex.Scopes

  describe "split/1" do
    test "nil requires nothing" do
      assert Scopes.split(nil) == []
    end

    test "an empty string requires nothing (no phantom \"\" scope)" do
      assert Scopes.split("") == []
    end

    test "splits a Shopify-formatted string" do
      assert Scopes.split("read_products,write_products") == ["read_products", "write_products"]
    end

    test "trims whitespace around scope names" do
      assert Scopes.split(" read_products , write_products ") ==
               ["read_products", "write_products"]
    end

    test "drops empty segments from leading, trailing and doubled commas" do
      assert Scopes.split(",read_products,,write_products,") ==
               ["read_products", "write_products"]
    end

    test "accepts a list of scope names and normalises each element" do
      assert Scopes.split([" read_orders", "", "write_orders "]) == [
               "read_orders",
               "write_orders"
             ]
    end

    test "preserves order" do
      assert Scopes.split("write_products,read_products") == ["write_products", "read_products"]
    end
  end

  describe "missing/2" do
    test "returns the required scopes the grant lacks, in required order" do
      assert Scopes.missing("write_orders,read_products,read_orders", "read_orders") ==
               ["write_orders", "read_products"]
    end

    test "returns [] when everything required is granted" do
      assert Scopes.missing("read_products", "read_products,write_products") == []
    end

    test "nothing required is never missing, whatever was granted" do
      assert Scopes.missing("", "read_products") == []
      assert Scopes.missing(nil, "read_products") == []
      assert Scopes.missing(nil, nil) == []
    end

    test "whitespace in the required list matches a Shopify-formatted grant" do
      assert Scopes.missing("read_products, write_products", "read_products,write_products") ==
               []
    end

    test "a scope required twice but granted once is not reported missing" do
      assert Scopes.missing("read_products,read_products", "read_products") == []
    end

    test "a nil grant is missing every required scope" do
      assert Scopes.missing("read_products", nil) == ["read_products"]
    end
  end
end
