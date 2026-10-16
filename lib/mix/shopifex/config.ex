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
    # Optional, legacy-OAuth only: Shopify managed installation does not use
    # these redirect URLs, so omit both unless your app still does its own
    # OAuth handshake.
    redirect_uri: "<%= tunnel_url %>/auth/install",
    reinstall_uri: "<%= tunnel_url %>/auth/update",
    webhook_uri: "<%= tunnel_url %>/webhook",
    payment_redirect_uri: "<%= tunnel_url %>/payment/complete",
    # Persistent, multi-node-safe billing redirect store (backed by the
    # shopifex_charge_redirects table this installer's migration creates). The
    # in-memory default is node-local and drops grants on multi-node deploys.
    redirect_after_agent: Shopifex.RedirectAfter.Ecto,
    scopes: "read_products",
    api_version: "2026-07", # Shopify Admin API version used for all GraphQL calls
    api_key: "your_shopify_api_key", #TODO: update
    secret: "shopifyapisecret456", #TODO: update
    webhook_topics: ["app/uninstalled"] # Subscribed via GraphQL on install. GDPR/compliance topics belong in shopify.app.toml, not here.
  """

  def gen(opts), do: EEx.eval_string(@template, opts)
end
