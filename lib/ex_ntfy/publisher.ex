defmodule ExNtfy.Publisher do
  @moduledoc """
  Publishing to ntfy topics — usually called through the `ExNtfy` facade.

  Three publish shapes, matching the ntfy API:

    * `publish/3` — JSON publish (`POST /`), the default path.
    * `publish_raw/3` — raw-body publish (`POST /<topic>`): the body passes
      through byte-identical and options travel as headers. This is the path
      for templating (`:template`) and webhook payloads.
    * `trigger/2` — webhook-style `GET /<topic>/trigger` with options only in
      the query string.

  All accept publish options (see `ExNtfy.Publish.Options`) mixed with client
  options (see `ExNtfy.Config`) in one keyword list.

  ## Telemetry

  Every request is wrapped in `:telemetry.span/3`, emitting
  `[:ex_ntfy, :publish, :start]`, `[:ex_ntfy, :publish, :stop]`, and
  `[:ex_ntfy, :publish, :exception]` with metadata `%{topic: topic,
  base_url: base_url}` — never credentials or message contents.
  """

  alias ExNtfy.{Client, Config, Error, Message}
  alias ExNtfy.Publish.Options

  @doc """
  Publishes a message as JSON (`POST /`).

  `message` may be `nil` for option-only publishes. Header-only options
  (`:cache`, `:firebase`, `:unified_push`, `:template`, `:poll_id`) are sent
  as headers on the same request.

  Returns the created message parsed from the server response.
  """
  @spec publish(String.t(), String.t() | nil, keyword()) ::
          {:ok, Message.t()} | {:error, Error.t()}
  def publish(topic, message, opts \\ []) do
    {client_opts, publish_opts} = split_opts(opts)
    {body, headers} = Options.to_json_body(topic, put_message(publish_opts, message))
    req = Client.new(client_opts)

    span(topic, req, fn ->
      req
      |> Client.request(method: :post, url: "/", json: body, headers: headers)
      |> parse_message()
    end)
  end

  @doc """
  Same as `publish/3`, but returns the message directly and raises
  `ExNtfy.Error` on failure.
  """
  @spec publish!(String.t(), String.t() | nil, keyword()) :: Message.t()
  def publish!(topic, message, opts \\ []) do
    case publish(topic, message, opts) do
      {:ok, message} -> message
      {:error, error} -> raise error
    end
  end

  @doc """
  Publishes a raw body to `POST /<topic>` — the body is sent byte-identical
  and every publish option becomes its canonical `X-` header (non-ASCII values
  RFC 2047-encoded).

  Use this for templating (reference §1.6), where the body is an arbitrary
  JSON payload rather than the ntfy publish schema, or for bodies that must
  not be re-encoded.
  """
  @spec publish_raw(String.t(), binary(), keyword()) :: {:ok, Message.t()} | {:error, Error.t()}
  def publish_raw(topic, body, opts \\ []) do
    {client_opts, publish_opts} = split_opts(opts)
    headers = Options.to_headers(publish_opts)
    req = Client.new(client_opts)

    span(topic, req, fn ->
      req
      |> Client.request(method: :post, url: topic_path(topic), body: body, headers: headers)
      |> parse_message()
    end)
  end

  @doc """
  Webhook-style publish: `GET /<topic>/trigger` with every option in the query
  string and no body. An empty `:message` defaults to `"triggered"` server-side.
  """
  @spec trigger(String.t(), keyword()) :: {:ok, Message.t()} | {:error, Error.t()}
  def trigger(topic, opts \\ []) do
    {client_opts, publish_opts} = split_opts(opts)
    params = Options.to_query(publish_opts)
    req = Client.new(client_opts)

    span(topic, req, fn ->
      req
      |> Client.request(method: :get, url: topic_path(topic) <> "/trigger", params: params)
      |> parse_message()
    end)
  end

  defp split_opts(opts), do: Keyword.split(opts, Config.keys())

  defp put_message(publish_opts, nil), do: publish_opts
  defp put_message(publish_opts, message), do: Keyword.put(publish_opts, :message, message)

  defp topic_path(topic), do: "/" <> URI.encode(topic, &URI.char_unreserved?/1)

  defp span(topic, req, fun) do
    metadata = %{topic: topic, base_url: req.options[:base_url]}
    :telemetry.span([:ex_ntfy, :publish], metadata, fn -> {fun.(), metadata} end)
  end

  defp parse_message({:ok, %Req.Response{body: body}}) when is_map(body) do
    case Message.from_map(body) do
      {:ok, message} -> {:ok, message}
      {:error, reason} -> {:error, %Error{reason: {:invalid_response, reason}}}
    end
  end

  defp parse_message({:ok, %Req.Response{body: body}}) do
    {:error, %Error{reason: {:invalid_response, body}}}
  end

  defp parse_message({:error, error}), do: {:error, error}
end
