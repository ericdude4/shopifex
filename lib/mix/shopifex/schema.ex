defmodule Mix.Shopifex.Schema do
  @moduledoc false

  alias Mix.Generator

  @template """
  defmodule <%= inspect schema.module %> do
    use Ecto.Schema
    import Ecto.Changeset
    <%= if schema.binary_id do %>
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id<% end %>
    schema <%= inspect schema.table %> do
      <%= for {k, v, o} <- schema.attrs do %>field <%= inspect k %>, <%= inspect v %>, <%= inspect o %>
      <% end %><%= for assoc <- schema.assocs do %>
      <%= assoc.type %> <%= inspect assoc.relation %>, <%= inspect assoc.related_schema %>, foreign_key: <%= inspect assoc.foreign_key %>
      <% end %>
      timestamps()
    end

    @doc false
    def changeset(<%= schema.var_name %>, attrs) do
      <%= schema.var_name %>
      |> cast(attrs, <%= inspect Enum.map(schema.attrs, fn
        {k, _, _} -> k
        {k, _} -> k
      end) %>)
      |> validate_required( <%= inspect Enum.map(schema.attrs, fn
        {k, _, _} -> k
        {k, _} -> k
      end) %>)
    end
  end
  """

  @payment_guard_template """
  defmodule <%= inspect module %> do
    use Shopifex.PaymentGuard

    @moduledoc \"\"\"
    For available callbacks, see https://hexdocs.pm/shopifex/Shopifex.PaymentGuard.html
    \"\"\"

  end
  """

  alias Mix.Shopifex.{Shop, Plan, Grant}

  @schemas [{"shop", Shop}, {"plan", Plan}, {"grant", Grant}]

  @spec create_schema_files(atom(), binary(), keyword()) :: any()
  def create_schema_files(context_app, namespace, opts) do
    app_base = Mix.Shopifex.app_base(context_app)

    for {table, schema} <- @schemas do
      table_name = "#{namespace}_#{table}s"
      var_name = "#{namespace}_#{table}"
      context = Macro.camelize("#{namespace}_shops")
      module = Macro.camelize("#{namespace}_#{table}")
      file = "#{Macro.underscore(module)}.ex"
      module = Module.concat([app_base, context, module])
      binary_id = Keyword.get(opts, :binary_id, false)

      attrs =
        schema.attrs()
        |> Kernel.++(Mix.Shopifex.Migration.attrs_from_assocs(schema.assocs(), namespace))

      assocs =
        schema.assocs()
        |> Enum.map(&build_assoc(&1, app_base, namespace, context))

      content =
        EEx.eval_string(@template,
          schema: %{
            module: module,
            table: table_name,
            var_name: var_name,
            binary_id: binary_id,
            attrs: attrs,
            assocs: assocs
          },
          otp_app: context_app
        )

      dir = "lib/#{context_app}/#{Macro.underscore(context)}/"

      File.mkdir_p!(dir)

      dir
      |> Path.join(file)
      |> Generator.create_file(content)
    end

    # Create the payment_guard boilerplate module
    dir = "lib/#{context_app}/"

    File.mkdir_p!(dir)

    file = "#{namespace}_payment_guard.ex"
    module = Macro.camelize("#{namespace}_payment_guard")
    module = Module.concat([app_base, module])

    content = EEx.eval_string(@payment_guard_template, module: module)

    dir
    |> Path.join(file)
    |> Generator.create_file(content)
  end

  defp build_assoc({:belongs_to, field, related_table}, app_base, namespace, _context) do
    related_context =
      String.to_atom("#{namespace}_#{related_table}")
      |> Atom.to_string()
      |> Macro.camelize()

    related_schema =
      String.to_atom("#{namespace}_#{related_table}")
      |> Atom.to_string()
      |> String.trim_trailing("s")
      |> Macro.camelize()

    related_schema = Module.concat([app_base, related_context, related_schema])

    foreign_key =
      field
      |> Atom.to_string()
      |> Kernel.<>("_id")
      |> String.to_atom()

    %{
      type: :belongs_to,
      relation: field,
      related_schema: related_schema,
      foreign_key: foreign_key
    }
  end

  defp build_assoc({:has_many, field, related_table}, app_base, namespace, context) do
    related_schema =
      String.to_atom("#{namespace}_#{related_table}")
      |> Atom.to_string()
      |> String.trim_trailing("s")
      |> Macro.camelize()

    foreign_key =
      context
      |> Macro.underscore()
      |> String.split("_")
      |> List.last()
      |> String.trim_trailing("s")
      |> Kernel.<>("_id")
      |> String.to_atom()

    related_schema = Module.concat([app_base, context, related_schema])

    %{
      type: :has_many,
      relation: field,
      related_schema: related_schema,
      foreign_key: foreign_key
    }
  end
end
