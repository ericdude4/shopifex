defmodule Shopifex.MixProject do
  use Mix.Project

  def project do
    [
      app: :shopifex,
      version: "0.1.5",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      compilers: [:phoenix, :gettext] ++ Mix.compilers(),
      deps: deps(),

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

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
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
      {:ex_doc, "~> 0.14", only: :dev, runtime: false}
    ]
  end
end
