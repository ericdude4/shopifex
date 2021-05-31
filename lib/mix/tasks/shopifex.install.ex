defmodule Mix.Tasks.Shopifex.Install do
  @shortdoc "Installs Shopifex"

  @moduledoc """
  Generates migrations, schema module files, and updates config.
        mix shopifex.install
  ## Arguments
    * `--context-app` - context app to use for path and module names
    * `--no-migration` - don't create migration file
    * `--no-schemas` - don't create schema module files
  """

  use Mix.Task

  alias Mix.{Ecto, Shopifex}
  alias Mix.Tasks.Shopifex.Gen.{Migration, Schemas, Controllers}

  @switches [context_app: :string, migration: :boolean, schemas: :boolean, controllers: :boolean]
  @default_opts [migration: true, schemas: true, controllers: true]
  @mix_task "shopifex.install"

  @impl true
  def run(args) do
    Shopifex.no_umbrella!(@mix_task)

    args
    |> Shopifex.parse_options(@switches, @default_opts)
    |> parse()
    |> run_migration(args)
    |> run_schemas(args)
    |> run_controllers(args)
    |> print_config_instructions(args)
  end

  defp parse({config, _parsed, _invalid}), do: config

  defp run_migration(%{migration: true} = config, args) do
    Migration.run(args)

    config
  end

  defp run_migration(config, _args), do: config

  defp run_schemas(%{schemas: true} = config, args) do
    Schemas.run(args)

    config
  end

  defp run_schemas(config, _args), do: config

  defp run_controllers(%{controllers: true} = config, args) do
    Controllers.run(args)

    config
  end

  defp run_controllers(config, _args), do: config

  defp print_config_instructions(config, args) do
    [repo | _repos] = Ecto.parse_repo(args)
    # context_app = Map.get(config, :context_app) || Shopifex.otp_app()
    # resource_owner = resource_owner(ProviderConfig.app_base(context_app))

    # content = Config.gen(context_app, repo: inspect(repo), resource_owner: resource_owner)
    content = ""

    Mix.shell().info("""
    Shopifex has been installed! Please append the following to `config/config.ex`:
    #{content}
    """)

    config
  end

  defp resource_owner(base), do: inspect(Module.concat([base, "Users", "User"]))
end
