defmodule Mix.Shopifex.Schema do
  @moduledoc false

  alias Mix.Generator
  alias Mix.Shopifex.Migration

  @template """
  defmodule <%= inspect schema.module %> do
    use Ecto.Schema
    import Ecto.Changeset
    <%= if schema.binary_id do %>
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id<% end %>
    schema <%= inspect schema.table %> do
      <%= for {k, v, o} <- schema.attrs do %>field <%= inspect k %>, <%= inspect v %>, <%= inspect o %>
      <% end %>
      timestamps()
    end

    @doc false
    def changeset(<%= schema.var_name %>, attrs) do
      <%= schema.var_name %>
      |> cast(attrs, <%= inspect Enum.map(schema.attrs, fn {k, _, _} -> k end) %>)
      |> validate_required(<%= inspect Enum.map(schema.attrs, fn {k, _, _} -> k end) %>)
    end
  end
  """

  alias Mix.Shopifex.Shop

  @schemas [{"shop", Shop}]

  @spec create_schema_files(atom(), binary(), keyword()) :: any()
  def create_schema_files(context_app, namespace, opts) do
    for {table, schema} <- @schemas do
      app_base = Mix.Shopifex.app_base(context_app)
      table_name = "#{namespace}_#{table}s"
      var_name = "#{namespace}_#{table}"
      context = Macro.camelize(table_name)
      module = Macro.camelize("#{namespace}_#{table}")
      file = "#{Macro.underscore(module)}.ex"
      module = Module.concat([app_base, context, module])
      binary_id = Keyword.get(opts, :binary_id, false)

      attrs =
        schema.attrs()
        |> Kernel.++(Migration.attrs_from_assocs(schema.assocs(), namespace))

      content =
        EEx.eval_string(@template,
          schema: %{
            module: module,
            table: table_name,
            var_name: var_name,
            binary_id: binary_id,
            attrs: attrs
          },
          otp_app: context_app
        )

      dir = "lib/#{context_app}/#{Macro.underscore(context)}/"

      File.mkdir_p!(dir)

      dir
      |> Path.join(file)
      |> Generator.create_file(content)
    end
  end
end
