defmodule Mix.Tasks.Shopifex.Gen.Controllers do
  @shortdoc "Generates Shopifex controller files"

  @moduledoc """
  Generates schema files.
      mix shopifex.gen.controller
      mix shopifex.gen.controller --namespace shopify_app
  ## Arguments
    * `--namespace` - namespace to prepend table, schema and controller module name
    * `--context-app` - context app to use for path and module names
  """
  use Mix.Task

  alias Mix.{Shopifex, Shopifex.Controller}

  @switches [context_app: :string, namespace: :string]
  @default_opts [namespace: "shopify"]
  @mix_task "shopifex.gen.controllers"

  @impl true
  def run(args) do
    Shopifex.no_umbrella!(@mix_task)

    args
    |> Shopifex.parse_options(@switches, @default_opts)
    |> parse()
    |> create_controller_files()
  end

  defp parse({config, _parsed, _invalid}), do: config

  defp create_controller_files(%{namespace: namespace} = config) do
    context_app = Map.get(config, :context_app) || Shopifex.otp_app()

    Controller.create_controller_files(context_app, namespace, [])
  end
end
