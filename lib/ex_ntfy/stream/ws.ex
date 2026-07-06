defmodule ExNtfy.Stream.WS do
  @moduledoc """
  WebSocket transport for `ExNtfy.Subscription` (`format: :ws`), subscribing
  via `GET /<topics>/ws` — requires the **optional** `:mint_web_socket`
  dependency:

      {:mint_web_socket, "~> 1.0"}

  Implements the subscription's internal transport contract (Mint connect →
  WebSocket upgrade; each text frame is one complete JSON message object, so
  there is no line reassembly). Server pings are answered with pongs
  internally; close frames and transport errors go through the subscription's
  normal reconnect flow. Binary frames are ignored (ntfy sends text).

  Auth works both ways on the upgrade request: the `Authorization` header, or
  `auth_via: :query` for the `?auth=` parameter — the canonical use case for
  the query encoding.
  """

  @behaviour ExNtfy.Subscription.Transport

  # False positive: dialyzer cannot track Mint's private conn state through
  # the Mint.WebSocket.stream/2 await loop and concludes Mint.WebSocket.new/5
  # can never return {:ok, conn, websocket}. It does (asserted by tests).
  @dialyzer {:nowarn_function, finish_upgrade: 3}

  alias ExNtfy.{Client, Config, Error, Message}

  @upgrade_timeout 15_000

  @typedoc "Parser state (frames need no buffering)."
  @opaque parser :: nil

  @doc false
  @spec ensure_available!() :: :ok
  def ensure_available! do
    dep = Application.get_env(:ex_ntfy, :ws_dependency, Mint.WebSocket)

    if Code.ensure_loaded?(dep) do
      :ok
    else
      raise ArgumentError,
            "format: :ws requires the optional dependency :mint_web_socket — " <>
              "add {:mint_web_socket, \"~> 1.0\"} to your deps"
    end
  end

  # -- Parser contract (each text frame is one complete JSON message) -------

  @doc "Returns a fresh parser state."
  @spec new() :: parser()
  def new, do: nil

  @doc "Parses one text frame via `ExNtfy.Message.from_json/1`."
  @spec feed(parser(), binary()) :: {[Message.t()], parser()}
  def feed(state, frame) do
    case Message.from_json(frame) do
      {:ok, message} -> {[message], state}
      {:error, _reason} -> {[], state}
    end
  end

  # -- Transport contract ----------------------------------------------------

  @impl ExNtfy.Subscription.Transport
  def connect(client_opts, path, params) do
    config = Config.resolve(client_opts)
    uri = URI.parse(config[:base_url])
    {http_scheme, ws_scheme} = schemes(uri.scheme)
    {auth_headers, auth_params} = Client.encode_auth(config[:auth], config[:auth_via])
    headers = [{"user-agent", Client.user_agent()} | auth_headers]
    full_path = path <> query_string(params ++ (auth_params || []))
    timeout = config[:receive_timeout] || @upgrade_timeout

    with {:ok, conn} <- Mint.HTTP.connect(http_scheme, uri.host, uri.port, protocols: [:http1]),
         {:ok, conn, ref} <- Mint.WebSocket.upgrade(ws_scheme, conn, full_path, headers) do
      await_upgrade(conn, ref, timeout, %{status: nil, headers: [], body: []})
    else
      {:error, reason} -> {:error, Error.from_exception(reason)}
      {:error, conn, reason} -> close_quietly(conn, Error.from_exception(reason))
    end
  end

  @impl ExNtfy.Subscription.Transport
  def handle_message({__MODULE__, :pending, ref}, %{ref: ref, pending: pending} = state) do
    entries = Enum.map(pending, &{:data, ref, &1})
    handle_entries(entries, %{state | pending: []})
  end

  def handle_message(message, %{conn: conn} = state) do
    case Mint.WebSocket.stream(conn, message) do
      {:ok, conn, entries} -> handle_entries(entries, %{state | conn: conn})
      {:error, conn, reason, _responses} -> transport_error(conn, reason)
      :unknown -> :unknown
    end
  end

  @impl ExNtfy.Subscription.Transport
  def close(state) do
    case send_frame(state, {:close, 1_000, ""}) do
      {:ok, state} -> Mint.HTTP.close(state.conn)
      {:error, _reason} -> Mint.HTTP.close(state.conn)
    end

    :ok
  end

  # -- Upgrade ----------------------------------------------------------------

  defp await_upgrade(conn, ref, timeout, acc) do
    receive do
      {tag, _socket, _payload} = message when tag in [:tcp, :ssl, :tcp_error, :ssl_error] ->
        upgrade_message(message, conn, ref, timeout, acc)

      {tag, _socket} = message when tag in [:tcp_closed, :ssl_closed] ->
        upgrade_message(message, conn, ref, timeout, acc)
    after
      timeout ->
        close_quietly(conn, Error.from_exception(%Mint.TransportError{reason: :timeout}))
    end
  end

  defp upgrade_message(message, conn, ref, timeout, acc) do
    case Mint.WebSocket.stream(conn, message) do
      {:ok, conn, entries} ->
        {acc, done?} = collect_upgrade(entries, acc)
        if done?, do: finish_upgrade(conn, ref, acc), else: await_upgrade(conn, ref, timeout, acc)

      {:error, conn, reason, _responses} ->
        close_quietly(conn, Error.from_exception(reason))

      :unknown ->
        # e.g. a straggler from a previous, already-canceled connection
        await_upgrade(conn, ref, timeout, acc)
    end
  end

  defp collect_upgrade(entries, acc) do
    Enum.reduce(entries, {acc, false}, fn
      {:status, _ref, status}, {acc, done?} -> {%{acc | status: status}, done?}
      {:headers, _ref, headers}, {acc, done?} -> {%{acc | headers: acc.headers ++ headers}, done?}
      {:data, _ref, data}, {acc, done?} -> {%{acc | body: [data | acc.body]}, done?}
      {:done, _ref}, {acc, _done?} -> {acc, true}
      _other, state -> state
    end)
  end

  defp finish_upgrade(conn, ref, %{status: 101} = acc) do
    case Mint.WebSocket.new(conn, ref, acc.status, acc.headers) do
      {:ok, conn, websocket} ->
        # WebSocket wire data can ride the same TCP segment as the 101 (a
        # server pushing immediately on connect). Stash it and poke ourselves
        # — connect/3 runs in the subscription process, so the synthetic
        # message lands in its handle_info and reaches handle_message/2.
        pending = Enum.reverse(acc.body)
        if pending != [], do: send(self(), {__MODULE__, :pending, ref})
        {:ok, %{conn: conn, ref: ref, websocket: websocket, pending: pending}}

      {:error, conn, reason} ->
        close_quietly(conn, Error.from_exception(reason))
    end
  end

  defp finish_upgrade(conn, _ref, acc) do
    # HTTP-level rejection (reason stays nil → fatal for the subscription)
    body = acc.body |> Enum.reverse() |> IO.iodata_to_binary()
    close_quietly(conn, Error.from_response(acc.status || 0, body))
  end

  # -- Established connection -------------------------------------------------

  defp handle_entries(entries, state) do
    result =
      Enum.reduce_while(entries, {:data, [], state}, fn
        {:data, ref, wire}, {:data, texts, %{ref: ref} = state} ->
          decode_wire(wire, texts, state)

        {:done, _ref}, {:data, texts, _state} ->
          {:halt, {:closed, texts, :closed}}

        _other, acc ->
          {:cont, acc}
      end)

    case result do
      {:data, texts, state} -> {:data, Enum.reverse(texts), state}
      {:closed, texts, reason} -> {:closed, Enum.reverse(texts), reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_wire(wire, texts, state) do
    case Mint.WebSocket.decode(state.websocket, wire) do
      {:ok, websocket, frames} ->
        handle_frames(frames, texts, %{state | websocket: websocket})

      {:error, _websocket, reason} ->
        {:halt, {:error, reason}}
    end
  end

  # The inner accumulator is the OUTER reduce_while directive, so the caller
  # can return this function's result directly.
  defp handle_frames(frames, texts, state) do
    Enum.reduce_while(frames, {:cont, {:data, texts, state}}, fn
      {:text, payload}, {:cont, {:data, texts, state}} ->
        {:cont, {:cont, {:data, [payload | texts], state}}}

      {:ping, data}, {:cont, {:data, texts, state}} ->
        case send_frame(state, {:pong, data}) do
          {:ok, state} -> {:cont, {:cont, {:data, texts, state}}}
          {:error, reason} -> {:halt, {:halt, {:error, reason}}}
        end

      {:close, code, reason}, {:cont, {:data, texts, _state}} ->
        {:halt, {:halt, {:closed, texts, {:remote_close, code, reason}}}}

      # pongs and binary frames (ntfy sends text) are ignored
      _other, acc ->
        {:cont, acc}
    end)
  end

  defp send_frame(state, frame) do
    with {:ok, websocket, wire} <- Mint.WebSocket.encode(state.websocket, frame),
         {:ok, conn} <- Mint.WebSocket.stream_request_body(state.conn, state.ref, wire) do
      {:ok, %{state | websocket: websocket, conn: conn}}
    else
      {:error, _conn_or_websocket, reason} -> {:error, reason}
    end
  end

  defp transport_error(conn, reason) do
    _ = Mint.HTTP.close(conn)
    {:error, reason}
  end

  defp close_quietly(conn, %Error{} = error) do
    _ = Mint.HTTP.close(conn)
    {:error, error}
  end

  defp schemes("https"), do: {:https, :wss}
  defp schemes(_http), do: {:http, :ws}

  defp query_string([]), do: ""
  defp query_string(params), do: "?" <> URI.encode_query(params)
end
