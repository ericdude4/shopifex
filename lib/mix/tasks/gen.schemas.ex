defmodule Mix.Tasks.Shopifex.Gen.Schemas do
  @shortdoc "Generates Shopifex schema files"

  @moduledoc """
  Generates schema files.
      mix shopifex.gen.schemas
      mix shopifex.gen.schemas --binary-id --namespace shopify_app
  ## Arguments
    * `--binary-id` - use binary id for primary keys
    * `--namespace` - namespace to prepend table and schema module name
    * `--context-app` - context app to use for path and module names
  """
  use Mix.Task

  alias Mix.{Shopifex, Shopifex.Schema}

  @switches     [binary_id: :boolean, context_app: :string, namespace: :string]
  @default_opts [binary_id: false, namespace: "shopify"]
  @mix_task     "shopifex.gen.schemas"

  @impl true
  def run(args) do
    Shopifex.no_umbrella!(@mix_task)

    args
    |> Shopifex.parse_options(@switches, @default_opts)
    |> parse()
    |> create_schema_files()
  end

  defp parse({config, _parsed, _invalid}), do: config

  defp create_schema_files(%{binary_id: binary_id, namespace: namespace} = config) do
   context_app = Map.get(config, :context_app) || Shopifex.otp_app()

    Schema.create_schema_files(context_app, namespace, binary_id: binary_id)
  end
end
