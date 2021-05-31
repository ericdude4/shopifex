defmodule Mix.Shopifex.Config do
  @moduledoc false

  @template """

  config :shopifex,
    repo: <%= repo %>,
    app_name: "<%= inspect app_base %> Shopify App",
    web_module: <%= inspect app_base %>Web,
    shop_schema: <%= inspect shop_schema %>,
    plan_schema: <%= inspect plan_schema %>,
    grant_schema: <%= inspect grant_schema %>,
    payment_guard: <%= inspect payment_guard %>,
    redirect_uri: "<%= tunnel_url %>/auth/install",
    reinstall_uri: "<%= tunnel_url %>/auth/update",
    webhook_uri: "<%= tunnel_url %>/webhook",
    payment_redirect_uri: "<%= tunnel_url %>/payment/complete",
    scopes: "read_products",
    api_key: "your_shopify_api_key", #TODO: update
    secret: "shopifyapisecret456", #TODO: update
    webhook_topics: ["app/uninstalled"] # These are automatically subscribed on a store upon install
  """

  def gen(opts), do: EEx.eval_string(@template, opts)
end
