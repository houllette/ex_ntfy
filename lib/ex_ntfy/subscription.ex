defmodule ExNtfy.Subscription do
  # The schema is defined as a plain variable so its generated docs can be
  # interpolated into @moduledoc below.
  schema_def = [
    topics: [
      type: {:or, [:string, {:list, :string}]},
      required: true,
      doc: "Topic(s) to subscribe to — a string, list, or comma-separated string."
    ],
    format: [
      type: {:in, [:json, :sse, :raw]},
      default: :json,
      doc:
        "Stream format. `:json` is the primary; `:raw` carries bodies only " <>
          "(no metadata, so no `since` resume)."
    ],
    handler: [
      type: {:custom, __MODULE__, :validate_handler, []},
      doc: "`{module, init_arg}` implementing `ExNtfy.Handler` (handler mode)."
    ],
    owner: [
      type: :pid,
      doc:
        "Receiver of `{:ntfy, pid, message}` / `{:ntfy_lifecycle, pid, event}` " <>
          "(message-passing mode; defaults to the caller). The subscription " <>
          "stops when the owner dies."
    ],
    reconnect: [
      type: :boolean,
      default: true,
      doc: "Reconnect with backoff on disconnect. `false` stops instead."
    ],
    reconnect_base_ms: [
      type: :pos_integer,
      default: 1_000,
      doc: "First backoff delay; doubles per attempt (plus jitter)."
    ],
    reconnect_max_ms: [
      type: :pos_integer,
      default: 60_000,
      doc: "Backoff cap."
    ],
    idle_timeout: [
      type: :pos_integer,
      default: 90_000,
      doc:
        "Watchdog: with no stream activity for this long (server keepalives " <>
          "arrive ~every 45 s), the connection is considered dead and rebuilt."
    ],
    name: [
      type: :any,
      doc: "Optional GenServer name, for supervision trees."
    ]
  ]

  @moduledoc """
  A long-lived subscription to ntfy topics — a GenServer owning one streaming
  HTTP connection, with automatic reconnect (resuming via `since=<last id>`),
  a keepalive watchdog, and two consumption styles.

  Usually started through `ExNtfy.subscribe/2`; use `start_link/1` directly
  in a supervision tree:

      children = [
        {ExNtfy.Subscription,
         topics: "alerts", handler: {MyHandler, []}, name: MyApp.NtfySub}
      ]

  In message-passing mode the owner receives `{:ntfy, pid, %ExNtfy.Message{}}`
  for messages and `{:ntfy_lifecycle, pid, event}` for `:connected`,
  `:disconnected`, `{:down, reason}`, and `{:message_clear | :message_delete,
  message}`. `open`/`keepalive` events are internal and never surface.

  Alongside the options below, all `ExNtfy.Subscribe.Options` (filters,
  `since`, `scheduled` — but not `poll`) and `ExNtfy.Config` client options
  are accepted. Req's own retry is disabled on the stream request — this
  module's reconnect loop is in charge.

  A non-2xx response is treated as fatal (it won't fix itself by retrying —
  think 403): the subscription delivers `{:down, %ExNtfy.Error{}}` and stops
  with `{:shutdown, error}` regardless of `reconnect:`.

  ## Telemetry

  `[:ex_ntfy, :subscription, :connected | :disconnected | :message]` with
  metadata `%{topics: topics}` — never credentials or message contents.

  ## Options

  #{NimbleOptions.docs(schema_def)}
  """

  use GenServer

  alias ExNtfy.{Client, Config, Error, Message}
  alias ExNtfy.Stream.{NDJSON, Raw, SSE}
  alias ExNtfy.Subscribe

  @schema NimbleOptions.new!(schema_def)
  @sub_keys Keyword.keys(schema_def)

  @parsers %{json: NDJSON, sse: SSE, raw: Raw}

  @doc """
  Starts a subscription linked to the caller. Options as described in the
  moduledoc; invalid options raise in the caller.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: do_start(:link, opts)

  @doc """
  Starts a subscription to `topics`. Sugar over `start_link/1` that defaults
  `owner:` to the caller in message-passing mode.
  """
  @spec subscribe(Subscribe.Options.topics(), keyword()) :: GenServer.on_start()
  def subscribe(topics, opts \\ []), do: start_link([topics: topics] ++ opts)

  @doc "Stops a subscription cleanly."
  @spec unsubscribe(GenServer.server()) :: :ok
  def unsubscribe(server), do: GenServer.stop(server, :normal)

  @doc """
  A lazy `Enumerable` of `ExNtfy.Message` structs — blocks the calling
  process. The underlying subscription starts on first demand and stops when
  the consumer halts (e.g. `Enum.take/2`) or exits.
  """
  @spec stream(Subscribe.Options.topics(), keyword()) :: Enumerable.t()
  def stream(topics, opts \\ []) do
    Stream.resource(
      fn ->
        {:ok, pid} = do_start(:nolink, [topics: topics, owner: self()] ++ opts)
        {pid, Process.monitor(pid)}
      end,
      fn {pid, ref} = acc ->
        case stream_receive(pid, ref) do
          {:message, message} -> {[message], acc}
          :halt -> {:halt, acc}
        end
      end,
      fn {pid, ref} ->
        Process.demonitor(ref, [:flush])

        try do
          GenServer.stop(pid, :normal)
        catch
          :exit, _reason -> :ok
        end
      end
    )
  end

  defp stream_receive(pid, ref) do
    receive do
      {:ntfy, ^pid, message} -> {:message, message}
      {:ntfy_lifecycle, ^pid, {:down, _reason}} -> :halt
      {:ntfy_lifecycle, ^pid, _event} -> stream_receive(pid, ref)
      {:DOWN, ^ref, :process, ^pid, _reason} -> :halt
    end
  end

  defp do_start(mode, opts) do
    {name, opts} = Keyword.pop(opts, :name)
    config = build_config!(opts)
    gen_opts = if name, do: [name: name], else: []

    case mode do
      :link -> GenServer.start_link(__MODULE__, config, gen_opts)
      :nolink -> GenServer.start(__MODULE__, config, gen_opts)
    end
  end

  # Validates everything in the caller, so bad options raise at the call site
  # rather than crashing the server on start.
  defp build_config!(opts) do
    opts =
      if Keyword.has_key?(opts, :handler) do
        opts
      else
        Keyword.put_new(opts, :owner, self())
      end

    {sub_specific, rest} = Keyword.split(opts, @sub_keys)
    sub_specific = NimbleOptions.validate!(sub_specific, @schema)
    {client_opts, subscribe_opts} = Keyword.split(rest, Config.keys())

    _ = Config.resolve(client_opts)
    _ = Subscribe.Options.to_query(subscribe_opts)
    path = Subscribe.Options.path(sub_specific[:topics], sub_specific[:format])

    sub_specific
    |> Map.new()
    |> Map.merge(%{client_opts: client_opts, subscribe_opts: subscribe_opts, path: path})
  end

  @impl GenServer
  def init(config) do
    {handler_mod, handler_state} =
      case config[:handler] do
        {mod, arg} ->
          Code.ensure_loaded!(mod)
          {:ok, handler_state} = mod.init(arg)
          {mod, handler_state}

        nil ->
          {nil, nil}
      end

    owner = config[:owner]
    owner_ref = if owner, do: Process.monitor(owner)

    state = %{
      topics: config.topics,
      path: config.path,
      parser_mod: Map.fetch!(@parsers, config.format),
      format: config.format,
      handler: handler_mod,
      handler_state: handler_state,
      owner: owner,
      owner_ref: owner_ref,
      reconnect: config.reconnect,
      reconnect_base_ms: config.reconnect_base_ms,
      reconnect_max_ms: config.reconnect_max_ms,
      idle_timeout: config.idle_timeout,
      subscribe_opts: config.subscribe_opts,
      req: Client.new(config.client_opts),
      resp: nil,
      parser: nil,
      connected?: false,
      last_id: nil,
      attempt: 0,
      idle_ref: nil,
      idle_timer: nil
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, state), do: do_connect(state)

  @impl GenServer
  def handle_info({:idle_timeout, ref}, %{idle_ref: ref} = state) do
    cancel_resp(state)
    handle_disconnect(%{state | idle_ref: nil, idle_timer: nil}, :idle_timeout)
  end

  def handle_info({:idle_timeout, _stale_ref}, state), do: {:noreply, state}

  def handle_info(:reconnect, state), do: do_connect(state)

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{owner_ref: ref} = state) do
    {:stop, :normal, state}
  end

  def handle_info(message, %{resp: resp} = state) when not is_nil(resp) do
    case Req.parse_message(resp, message) do
      {:ok, chunks} -> process_chunks(chunks, state)
      {:error, reason} -> handle_disconnect(state, {:transport, reason})
      :unknown -> {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    cancel_resp(state)
  end

  defp do_connect(state) do
    request_opts = [
      method: :get,
      url: state.path,
      params: query_params(state),
      into: :self,
      retry: false
    ]

    case Client.request(state.req, request_opts) do
      {:ok, %Req.Response{} = resp} ->
        state = %{state | resp: resp, parser: state.parser_mod.new(), connected?: true}
        # :raw has no open event to confirm the stream, so reset backoff here.
        state = if state.format == :raw, do: %{state | attempt: 0}, else: state
        telemetry(:connected, state)
        state = notify_lifecycle(state, :connected)
        {:noreply, reset_idle(state)}

      {:error, %Error{reason: nil} = error} ->
        # An HTTP error status (e.g. 403) won't fix itself by retrying.
        go_down(state, error)

      {:error, %Error{} = error} ->
        maybe_reconnect(state, error)
    end
  end

  defp query_params(state) do
    state.subscribe_opts
    |> maybe_resume(state.last_id)
    |> Subscribe.Options.to_query()
  end

  defp maybe_resume(subscribe_opts, nil), do: subscribe_opts
  defp maybe_resume(subscribe_opts, last_id), do: Keyword.put(subscribe_opts, :since, last_id)

  defp process_chunks(chunks, state) do
    Enum.reduce_while(chunks, {:noreply, state}, fn
      {:data, data}, {:noreply, state} ->
        state = reset_idle(state)
        {messages, parser} = state.parser_mod.feed(state.parser, data)
        state = Enum.reduce(messages, %{state | parser: parser}, &route_message/2)
        {:cont, {:noreply, state}}

      :done, {:noreply, state} ->
        {:halt, handle_disconnect(state, :closed)}

      {:trailers, _trailers}, acc ->
        {:cont, acc}
    end)
  end

  defp route_message(%Message{event: :open}, state), do: %{state | attempt: 0}
  defp route_message(%Message{event: :keepalive}, state), do: state

  defp route_message(%Message{event: :message} = message, state) do
    telemetry(:message, state)
    state = %{state | last_id: message.id || state.last_id}
    deliver_message(state, message)
  end

  defp route_message(%Message{event: event} = message, state)
       when event in [:message_clear, :message_delete] do
    notify_lifecycle(state, {event, message})
  end

  defp route_message(_message, state), do: state

  defp deliver_message(%{handler: nil, owner: owner} = state, message) do
    send(owner, {:ntfy, self(), message})
    state
  end

  defp deliver_message(%{handler: mod} = state, message) do
    {:ok, handler_state} = mod.handle_message(message, state.handler_state)
    %{state | handler_state: handler_state}
  end

  defp notify_lifecycle(%{handler: nil, owner: owner} = state, event) do
    send(owner, {:ntfy_lifecycle, self(), event})
    state
  end

  defp notify_lifecycle(%{handler: mod} = state, event) do
    if function_exported?(mod, :handle_lifecycle, 2) do
      {:ok, handler_state} = mod.handle_lifecycle(event, state.handler_state)
      %{state | handler_state: handler_state}
    else
      state
    end
  end

  defp handle_disconnect(state, reason) do
    state = cancel_idle(state)

    state =
      if state.connected? do
        telemetry(:disconnected, state)

        %{state | connected?: false, resp: nil, parser: nil}
        |> notify_lifecycle(:disconnected)
      else
        %{state | resp: nil, parser: nil}
      end

    maybe_reconnect(state, reason)
  end

  defp maybe_reconnect(%{reconnect: true} = state, _reason) do
    attempt = state.attempt + 1
    Process.send_after(self(), :reconnect, backoff_delay(state, attempt))
    {:noreply, %{state | attempt: attempt}}
  end

  defp maybe_reconnect(state, reason), do: go_down(state, reason)

  defp go_down(state, reason) do
    state = notify_lifecycle(state, {:down, reason})
    {:stop, {:shutdown, reason}, state}
  end

  # Exponential backoff with jitter: base * 2^(attempt-1), capped, +0..25%.
  defp backoff_delay(state, attempt) do
    capped = min(state.reconnect_base_ms * Integer.pow(2, attempt - 1), state.reconnect_max_ms)
    capped + :rand.uniform(max(div(capped, 4), 1)) - 1
  end

  defp reset_idle(state) do
    state = cancel_idle(state)
    ref = make_ref()
    timer = Process.send_after(self(), {:idle_timeout, ref}, state.idle_timeout)
    %{state | idle_ref: ref, idle_timer: timer}
  end

  defp cancel_idle(%{idle_timer: nil} = state), do: state

  defp cancel_idle(state) do
    Process.cancel_timer(state.idle_timer)
    %{state | idle_timer: nil, idle_ref: nil}
  end

  defp cancel_resp(%{resp: nil}), do: :ok
  defp cancel_resp(%{resp: resp}), do: Req.cancel_async_response(resp)

  defp telemetry(event, state) do
    :telemetry.execute(
      [:ex_ntfy, :subscription, event],
      %{system_time: System.system_time()},
      %{topics: state.topics}
    )
  end

  @doc false
  @spec validate_handler(term()) :: {:ok, {module(), term()}} | {:error, String.t()}
  def validate_handler({mod, _arg} = handler) when is_atom(mod), do: {:ok, handler}

  def validate_handler(other) do
    {:error, "expected {module, init_arg} implementing ExNtfy.Handler, got: #{inspect(other)}"}
  end
end
