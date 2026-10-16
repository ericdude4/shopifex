defmodule Shopifex.MixProject do
  use Mix.Project

  def project do
    [
      app: :shopifex,
      version: "2.4.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      compilers: Mix.compilers(),
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      # Hex
      description: "Phoenix boilerplate for Shopify Embedded App SDK",
      package: [
        maintainers: ["Eric Froese"],
        licenses: ["Apache-2.0"],
        links: %{
          "GitHub" => "https://github.com/ericdude4/shopifex"
        },
        files:
          ~w(lib LICENSE mix.exs README.md CHANGELOG.md docs/parity-matrix.md docs/upgrading.md)
      ],
      # Docs
      name: "Shopifex",
      source_url: "https://github.com/ericdude4/shopifex",
      homepage_url: "https://github.com/ericdude4/shopifex",
      docs: [
        # The main page in the docs
        main: "Shopifex",
        logo: "guides/images/s.png",
        extras: ["README.md", "CHANGELOG.md", "docs/parity-matrix.md", "docs/upgrading.md"],
        filter_prefix: "Shopifex"
      ]
    ]
  end

  # A hack to bypass default env (https://stackoverflow.com/questions/51788263/module-conncase-is-not-loaded-and-could-not-be-found)
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
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_ecto, "~> 4.6"},
      {:ecto_sql, "~> 3.12"},
      # The library itself never calls Postgrex; it's only needed to run the
      # dummy app's repo in dev/test. Downstream apps bring their own driver.
      {:postgrex, ">= 0.0.0", only: [:dev, :test]},
      {:phoenix_html, ">= 4.0.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.0"},
      {:jose, "~> 1.11"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:cors_plug, "~> 2.0 or ~> 3.0"},
      {:req, "~> 0.5"}
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
