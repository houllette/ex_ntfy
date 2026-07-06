defmodule ExNtfy.WSTestServer do
  @moduledoc """
  Minimal Bandit + WebSock server for WebSocket transport tests.

  Each accepted connection reports `{:ws_connected, sock_pid, conn_info}` to
  the test (with the upgrade request's path/params/headers), then obeys:

    * `{:push, frame}` — push any WebSock frame (e.g. `{:text, json}`,
      `{:ping, data}`)
    * `:close` — close with code 1000

  Client pong frames are reported as `{:ws_pong, data}`.
  """

  defmodule Sock do
    @moduledoc false
    @behaviour WebSock

    @impl WebSock
    def init(state) do
      send(state.test_pid, {:ws_connected, self(), state.conn_info})

      case state do
        # Push immediately so the frame rides right behind the 101 handshake —
        # exercises the client's pending-data path for same-segment arrivals.
        %{push_on_init: payload} -> {:push, {:text, payload}, state}
        _no_push -> {:ok, state}
      end
    end

    @impl WebSock
    def handle_in({_payload, _opts}, state), do: {:ok, state}

    @impl WebSock
    def handle_control({data, opcode: :pong}, state) do
      send(state.test_pid, {:ws_pong, data})
      {:ok, state}
    end

    def handle_control(_frame, state), do: {:ok, state}

    @impl WebSock
    def handle_info({:push, frame}, state), do: {:push, frame, state}
    def handle_info(:close, state), do: {:stop, :normal, 1000, state}
    def handle_info(_other, state), do: {:ok, state}
  end

  defmodule Router do
    @moduledoc false
    @behaviour Plug

    @impl Plug
    def init(opts), do: opts

    @impl Plug
    def call(%{request_path: "/reject" <> _rest} = conn, _opts) do
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(403, JSON.encode!(%{"code" => 40_301, "http" => 403}))
    end

    def call(conn, %{test_pid: test_pid}) do
      conn = Plug.Conn.fetch_query_params(conn)

      conn_info = %{
        path: conn.request_path,
        params: conn.query_params,
        headers: Map.new(conn.req_headers)
      }

      sock_state = %{test_pid: test_pid, conn_info: conn_info}

      sock_state =
        if String.starts_with?(conn.request_path, "/push-on-init") do
          Map.put(sock_state, :push_on_init, JSON.encode!(ExNtfy.Fixtures.full_message_map()))
        else
          sock_state
        end

      WebSockAdapter.upgrade(conn, Sock, sock_state, [])
    end
  end

  @doc """
  Child spec for `start_supervised!/1`: a Bandit server on a random loopback
  port routing every request to the upgrade plug.
  """
  def child_spec(test_pid) do
    Supervisor.child_spec(
      {Bandit, plug: {Router, %{test_pid: test_pid}}, port: 0, ip: :loopback, startup_log: false},
      id: __MODULE__
    )
  end

  @doc "The port a started Bandit server is listening on."
  def port(server_pid) do
    {:ok, {_address, port}} = ThousandIsland.listener_info(server_pid)
    port
  end
end
