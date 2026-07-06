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

  @doc """
  Uploads a binary attachment: `PUT /<topic>` with the file as the request
  body (reference §1.4).

  `body` may be iodata, an `Enumerable` of chunks, or `{:file, path}` — the
  latter streams from disk without reading the whole file into memory, and
  defaults `:filename` to `Path.basename(path)`. All publish options ride
  along as headers (the body is the file, so this is the header path); use
  `:message` for the notification text shown alongside the attachment.

  Server limits apply (~2 MB per file on ntfy.sh); an oversized upload comes
  back as `{:error, %ExNtfy.Error{http: 413}}`.
  """
  @spec publish_file(String.t(), iodata() | Enumerable.t() | {:file, Path.t()}, keyword()) ::
          {:ok, Message.t()} | {:error, Error.t()}
  def publish_file(topic, body, opts \\ []) do
    {body, opts} = file_body(body, opts)
    {client_opts, publish_opts} = split_opts(opts)
    headers = Options.to_headers(publish_opts)
    req = Client.new(client_opts)

    span(topic, req, fn ->
      req
      |> Client.request(method: :put, url: topic_path(topic), body: body, headers: headers)
      |> parse_message()
    end)
  end

  @doc """
  Same as `publish_file/3`, but returns the message directly and raises
  `ExNtfy.Error` on failure.
  """
  @spec publish_file!(String.t(), iodata() | Enumerable.t() | {:file, Path.t()}, keyword()) ::
          Message.t()
  def publish_file!(topic, body, opts \\ []) do
    case publish_file(topic, body, opts) do
      {:ok, message} -> message
      {:error, error} -> raise error
    end
  end

  @doc """
  Updates a delivered notification by publishing again with the same sequence
  ID (reference §1.7) — sugar over `publish/3` with `:sequence_id` set.

  Two idioms: reuse the `id` of a previously returned message as the sequence
  ID for follow-ups, or pick your own sequence ID up front on the first
  publish (`sequence_id:` option) and keep using it.
  """
  @spec update(String.t(), String.t(), String.t() | nil, keyword()) ::
          {:ok, Message.t()} | {:error, Error.t()}
  def update(topic, sequence_id, message, opts \\ []) do
    publish(topic, message, Keyword.put(opts, :sequence_id, sequence_id))
  end

  @doc """
  Clears (marks read and dismisses) a delivered notification:
  `PUT /<topic>/<sequence_id>/clear`. The server also accepts a `/read` alias
  and a `GET` form for header-limited clients; this SDK exposes only the
  canonical endpoint.

  Returns the emitted `event: :message_clear` message.
  """
  @spec clear(String.t(), String.t(), keyword()) :: {:ok, Message.t()} | {:error, Error.t()}
  def clear(topic, sequence_id, opts \\ []) do
    lifecycle(topic, sequence_id, opts, :put, "/clear")
  end

  @doc """
  Deletes a notification from clients: `DELETE /<topic>/<sequence_id>`.
  History remains server-side (storage is append-only), and a deleted
  sequence revives if republished.

  Returns the emitted `event: :message_delete` message.
  """
  @spec delete(String.t(), String.t(), keyword()) :: {:ok, Message.t()} | {:error, Error.t()}
  def delete(topic, sequence_id, opts \\ []) do
    lifecycle(topic, sequence_id, opts, :delete, "")
  end

  @file_chunk_bytes 64 * 1024

  defp file_body({:file, path}, opts) do
    {File.stream!(path, @file_chunk_bytes), Keyword.put_new(opts, :filename, Path.basename(path))}
  end

  defp file_body(body, opts), do: {body, opts}

  # Lifecycle endpoints take no publish options, so `opts` are client options
  # only — unknown keys raise in Config.
  defp lifecycle(topic, sequence_id, client_opts, method, suffix) do
    url = topic_path(topic) <> "/" <> path_segment(sequence_id) <> suffix
    req = Client.new(client_opts)

    span(topic, req, fn ->
      req
      |> Client.request(method: method, url: url)
      |> parse_message()
    end)
  end

  defp split_opts(opts), do: Keyword.split(opts, Config.keys())

  defp put_message(publish_opts, nil), do: publish_opts
  defp put_message(publish_opts, message), do: Keyword.put(publish_opts, :message, message)

  defp topic_path(topic), do: "/" <> path_segment(topic)

  defp path_segment(segment), do: URI.encode(segment, &URI.char_unreserved?/1)

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
