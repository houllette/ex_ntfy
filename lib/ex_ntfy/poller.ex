defmodule ExNtfy.Poller do
  @moduledoc """
  One-shot retrieval of cached messages — the `poll=1` mode of the subscribe
  API (reference §2.1–§2.2). Usually called through the `ExNtfy` facade.

  Polling is a plain request/response: the server returns cached messages as
  ndjson and closes the connection. Long-lived streaming subscriptions are
  separate (Phase 6).

  ## Telemetry

  Every poll is wrapped in `:telemetry.span/3`, emitting
  `[:ex_ntfy, :poll, :start | :stop | :exception]` with metadata
  `%{topics: topics, base_url: base_url}` — never credentials or message
  contents.
  """

  require Logger

  alias ExNtfy.{Client, Config, Error, Message}
  alias ExNtfy.Subscribe.Options

  @doc """
  Fetches cached messages: `GET /<topics>/json?poll=1`.

  `topics` is a string or list of strings (joined with commas in the path).
  Options are the subscribe options (see `ExNtfy.Subscribe.Options`) plus any
  client options; the default window is `since: :all` server-side.

  Returns messages in the order the server sent them. `open`/`keepalive`
  events are dropped from the result (poll responses normally contain only
  cached `message` events anyway); unparsable ndjson lines are skipped with a
  `Logger` warning rather than failing the whole poll.
  """
  @spec poll(Options.topics(), keyword()) :: {:ok, [Message.t()]} | {:error, Error.t()}
  def poll(topics, opts \\ []) do
    {client_opts, sub_opts} = Keyword.split(opts, Config.keys())
    params = [poll: "1"] ++ Options.to_query(sub_opts)
    url = Options.path(topics, :json)
    req = Client.new(client_opts)
    metadata = %{topics: topics, base_url: req.options[:base_url]}

    :telemetry.span([:ex_ntfy, :poll], metadata, fn ->
      result =
        case Client.request(req, method: :get, url: url, params: params) do
          {:ok, %Req.Response{body: body}} -> parse_body(body)
          {:error, error} -> {:error, error}
        end

      {result, metadata}
    end)
  end

  @doc """
  Same as `poll/2`, but returns the message list directly and raises
  `ExNtfy.Error` on failure.
  """
  @spec poll!(Options.topics(), keyword()) :: [Message.t()]
  def poll!(topics, opts \\ []) do
    case poll(topics, opts) do
      {:ok, messages} -> messages
      {:error, error} -> raise error
    end
  end

  defp parse_body(body) when is_binary(body) do
    messages =
      body
      |> String.split("\n", trim: true)
      |> Enum.flat_map(&parse_line/1)
      |> Enum.reject(&(&1.event in [:open, :keepalive]))

    {:ok, messages}
  end

  defp parse_body(body), do: {:error, %Error{reason: {:invalid_response, body}}}

  defp parse_line(line) do
    case Message.from_json(line) do
      {:ok, message} ->
        [message]

      {:error, reason} ->
        Logger.warning("ExNtfy.poll skipping unparsable ndjson line: #{inspect(reason)}")
        []
    end
  end
end
