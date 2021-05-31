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

  alias Mix.{Ecto, Shopifex, Shopifex.Config}
  alias Mix.Tasks.Shopifex.Gen.{Migration, Schemas, Controllers}

  @switches [context_app: :string, migration: :boolean, schemas: :boolean, controllers: :boolean]
  @default_opts [migration: true, schemas: true, controllers: true, namespace: "shopify"]
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

  defp print_config_instructions(%{namespace: namespace} = config, args) do
    [repo | _repos] = Ecto.parse_repo(args)
    context_app = Map.get(config, :context_app) || Shopifex.otp_app()
    app_base = Mix.Shopifex.app_base(context_app)
    schema_context = Module.concat([app_base, Macro.camelize("#{namespace}_shops")])
    shop_schema = Module.concat(schema_context, Macro.camelize("#{namespace}_shop"))
    plan_schema = Module.concat(schema_context, Macro.camelize("#{namespace}_plan"))
    grant_schema = Module.concat(schema_context, Macro.camelize("#{namespace}_grant"))
    payment_guard = Module.concat([app_base, Macro.camelize("#{namespace}_payment_guard")])

    camel_namespace = Macro.camelize("#{namespace}")

    tunnel_url =
      Mix.Shell.IO.prompt("Enter tunnel URL (https://myapp.ngrok.io):")
      |> String.trim_trailing("\n")

    content =
      Config.gen(
        repo: inspect(repo),
        app_base: app_base,
        shop_schema: shop_schema,
        plan_schema: plan_schema,
        grant_schema: grant_schema,
        payment_guard: payment_guard,
        tunnel_url: tunnel_url,
        camel_namespace: camel_namespace
      )

    print_white("Shopifex has been installed! Please append the following to `config/config.ex`:")

    Mix.shell().info("#{content}")

    print_white("Add the following routes to `lib/#{context_app}_web/router.ex`:")

    """

      require ShopifexWeb.Routes

      ShopifexWeb.Routes.pipelines()

      # Include all auth (when Shopify requests to render your app in an iframe), installation and update routes
      ShopifexWeb.Routes.auth_routes(<%= inspect app_base %>Web.<%= camel_namespace %>AuthController)

      # Include all payment routes
      ShopifexWeb.Routes.payment_routes(<%= inspect app_base %>Web.<%= camel_namespace %>PaymentController)

      # Endpoints accessible within the Shopify admin panel iFrame.
      # Don't include this scope block if you are creating a SPA.
      scope "/", <%= inspect app_base %>Web do
        pipe_through [:shopifex_browser, :shopify_session]

        get "/", PageController, :index
      end

      # Make your webhook endpoint look like this
      scope "/webhook", <%= inspect app_base %>Web do
        pipe_through [:shopify_webhook]

        post "/", <%= camel_namespace %>WebhookController, :action
      end

      # Place your admin link endpoints in here. TODO: create this controller
      scope "/admin-links", <%= inspect app_base %>Web do
        pipe_through [:shopify_admin_link]

        # get "/do-a-thing", <%= camel_namespace %>AdminLinkController, :do_a_thing
      end
    """
    |> EEx.eval_string(app_base: app_base, camel_namespace: camel_namespace)
    |> Mix.shell().info()

    config
  end

  defp print_white(text) do
    (IO.ANSI.white_background() <>
       IO.ANSI.black() <>
       text <>
       IO.ANSI.reset())
    |> Mix.shell().info()
  end
end
