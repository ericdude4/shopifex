defmodule Shopifex.Plug.LoadInIframe do
  @moduledoc """
  Allows the response to render inside the Shopify admin iframe.

  Phoenix's `put_secure_browser_headers/2` blocks cross-origin framing twice:
  with `x-frame-options` and, since Phoenix 1.8, with a `frame-ancestors 'self'`
  directive in its default `content-security-policy`. Browsers enforce every
  CSP header on a response, so leaving that directive in place blocks the admin
  even when `Shopifex.Plug.SetCSPHeader` adds its own policy alongside it.

  This plug deletes `x-frame-options` and drops the `frame-ancestors` directive
  from each `content-security-policy` header, keeping the policy's other
  directives (such as `base-uri 'self'`). A header left with no directives is
  removed. Pipe through `Shopifex.Plug.SetCSPHeader` (the `:shopify_embedded`
  pipeline) afterwards to restrict framing to the Shopify admin.
  """

  @csp_header "content-security-policy"

  def init(options) do
    # initialize options
    options
  end

  def call(conn, _) do
    conn
    |> Plug.Conn.delete_resp_header("x-frame-options")
    |> drop_frame_ancestors()
  end

  defp drop_frame_ancestors(conn) do
    case Plug.Conn.get_resp_header(conn, @csp_header) do
      [] ->
        conn

      policies ->
        # Each header is a separate policy (browsers enforce all of them), so
        # rewrite them one by one rather than merging them into one.
        remaining =
          policies
          |> Enum.map(&without_frame_ancestors/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.map(&{@csp_header, &1})

        # `delete_resp_header/2` removes only the first header with the name.
        policies
        |> Enum.reduce(conn, fn _, conn -> Plug.Conn.delete_resp_header(conn, @csp_header) end)
        |> Plug.Conn.prepend_resp_headers(remaining)
    end
  end

  defp without_frame_ancestors(policy) do
    directives =
      policy
      |> String.split(";")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or frame_ancestors?(&1)))

    case directives do
      [] -> ""
      directives -> Enum.join(directives, "; ") <> ";"
    end
  end

  # CSP directive names are case-insensitive.
  defp frame_ancestors?(directive) do
    [name | _] = String.split(directive, ~r/\s+/, parts: 2)
    String.downcase(name) == "frame-ancestors"
  end
end
