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
    <%= extra_funs %>
  end
  """

  @webhook_boilerplate """

    # add as many handle_topic/3 functions here as you like! This basic one handles app uninstallation
    def handle_topic(conn, shop, "app/uninstalled") do
      Shopifex.Shops.delete_shop(shop)

      conn
      |> send_resp(200, "success")
    end

    # Mandatory Shopify shop data erasure GDPR webhook. Simply delete the shop record
    def handle_topic(conn, shop, "shop/redact") do
      Shopifex.Shops.delete_shop(shop)

      conn
      |> send_resp(204, "")
    end

    # Mandatory Shopify customer data erasure GDPR webhook. Simply delete the shop (customer) record
    def handle_topic(conn, shop, "customers/redact") do
      Shopifex.Shops.delete_shop(shop)

      conn
      |> send_resp(204, "")
    end

    # Mandatory Shopify customer data request GDPR webhook.
    def handle_topic(conn, _shop, "customers/data_request") do
      # Send an email of the shop data to the customer.
      conn
      |> send_resp(202, "Accepted")
    end
  """

  @controllers [
    {"auth_controller", ""},
    {"webhook_controller", @webhook_boilerplate}
  ]

  @spec create_controller_files(atom(), binary(), keyword()) :: any()
  def create_controller_files(context_app, namespace, _opts) do
    for {controller, extra_funs} <- @controllers do
      app_base = Mix.Shopifex.app_base(context_app)
      controller_module = Macro.camelize("#{namespace}_#{controller}")
      file = "#{Macro.underscore(controller_module)}.ex"
      uses = Macro.camelize(controller)

      content =
        EEx.eval_string(@template,
          namespace: namespace,
          controller_module: controller_module,
          app_base: app_base,
          uses: uses,
          extra_funs: extra_funs
        )

      dir = "lib/#{context_app}_web/controllers/"

      File.mkdir_p!(dir)

      dir
      |> Path.join(file)
      |> Generator.create_file(content)
    end
  end
end
