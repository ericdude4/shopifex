defmodule Mix.Shopifex.Controller do
  @moduledoc false

  alias Mix.Generator

  @template """
  defmodule <%= inspect app_base %>Web.<%= controller_module %> do
    use <%= inspect app_base %>Web, :controller
    use ShopifexWeb.<%= uses %>

    @moduledoc \"\"\"
    For available callbacks, see https://hexdocs.pm/shopifex/ShopifexWeb.<%= uses %>.html
    \"\"\"
  end
  """

  @controllers ["auth_controller"]

  @spec create_controller_files(atom(), binary(), keyword()) :: any()
  def create_controller_files(context_app, namespace, _opts) do
    for controller <- @controllers do
      app_base = Mix.Shopifex.app_base(context_app)
      controller_module = Macro.camelize("#{namespace}_#{controller}")
      file = "#{Macro.underscore(controller_module)}.ex"
      uses = Macro.camelize(controller)

      content =
        EEx.eval_string(@template,
          namespace: namespace,
          controller_module: controller_module,
          app_base: app_base,
          uses: uses
        )

      dir = "lib/#{context_app}_web/controllers/"

      File.mkdir_p!(dir)

      dir
      |> Path.join(file)
      |> Generator.create_file(content)
    end
  end
end
