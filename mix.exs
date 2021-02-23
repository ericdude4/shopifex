defmodule Shopifex.MixProject do
  use Mix.Project

  def project do
    [
      app: :shopifex,
      version: "0.4.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      compilers: [:phoenix, :gettext] ++ Mix.compilers(),
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      # Hex
      description: "Phoenix boilerplate for Shopify Embedded App SDK",
      package: [
        maintainers: ["Eric Froese"],
        licenses: ["Apache-2.0"],
        links: %{
          "GitHub" => "https://github.com/ericdude4/shopifex",
          "ericfroese.ca" => "https://ericfroese.ca"
        }
      ],
      # Docs
      name: "Shopifex",
      source_url: "https://github.com/ericdude4/shopifex",
      homepage_url: "https://github.com/ericdude4/shopifex",
      docs: [
        # The main page in the docs
        main: "Shopifex",
        extras: ["README.md"]
      ]
    ]
  end

  # A hack to bypass default env (https://stackoverflow.com/questions/51788263/module-conncase-is-not-loaded-and-could-not-be-found)
  defp elixirc_paths(:dev), do: ["lib", "test/support"]
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Shopifex.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix, "~> 1.5.1"},
      {:phoenix_ecto, "~> 4.1"},
      {:ecto_sql, "~> 3.4"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 2.11"},
      {:gettext, "~> 0.11"},
      {:jason, "~> 1.0"},
      {:plug_cowboy, "~> 2.0"},
      {:shopify, "~> 0.4"},
      {:ex_doc, "~> 0.14", only: :dev, runtime: false},
      {:react_phoenix, "~> 1.2"}
    ]
  end

  defp aliases do
    [
      test: [
        "ecto.create --quiet --repo ShopifexDummy.Repo",
        "ecto.migrate --quiet --repo ShopifexDummy.Repo --migrations-path test/support/shopifex_dummy/priv/repo/migrations",
        "test"
      ]
    ]
  end
end
