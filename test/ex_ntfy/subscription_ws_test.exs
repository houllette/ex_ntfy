defmodule ExNtfy.SubscriptionWSTest do
  use ExUnit.Case, async: true

  alias ExNtfy.{Fixtures, Message, Subscription, WSTestServer}

  @moduletag capture_log: true

  @fast [reconnect_base_ms: 20, reconnect_max_ms: 100]

  setup do
    server = start_supervised!(WSTestServer.child_spec(self()))
    {:ok, base_url: "http://localhost:#{WSTestServer.port(server)}"}
  end

  defp subscribe_ws(base_url, opts \\ []) do
    {:ok, pid} =
      ExNtfy.subscribe("mytopic", [base_url: base_url, format: :ws] ++ @fast ++ opts)

    pid
  end

  defp push_json(sock, map), do: send(sock, {:push, {:text, JSON.encode!(map)}})

  describe "upgrade request" do
    test "GETs /<topics>/ws with the shared query builder", %{base_url: base_url} do
      {:ok, pid} =
        ExNtfy.subscribe(
          ["alerts", "backups"],
          [base_url: base_url, format: :ws, since: "10m", priority: [:high, 5]] ++ @fast
        )

      assert_receive {:ws_connected, _sock, conn_info}, 1_000
      assert conn_info.path == "/alerts,backups/ws"
      assert conn_info.params == %{"since" => "10m", "priority" => "4,5"}

      assert_receive {:ntfy_lifecycle, ^pid, :connected}, 1_000
      assert :ok = ExNtfy.unsubscribe(pid)
    end

    test "token auth rides the Authorization header on the upgrade", %{base_url: base_url} do
      pid = subscribe_ws(base_url, auth: {:token, "tk_mytoken"})

      assert_receive {:ws_connected, _sock, conn_info}, 1_000
      assert conn_info.headers["authorization"] == "Bearer tk_mytoken"
      assert conn_info.params == %{}

      assert :ok = ExNtfy.unsubscribe(pid)
    end

    test "auth_via: :query encodes the Authorization value into ?auth=", %{base_url: base_url} do
      pid = subscribe_ws(base_url, auth: {:token, "tk_mytoken"}, auth_via: :query, since: :latest)

      assert_receive {:ws_connected, _sock, conn_info}, 1_000
      refute Map.has_key?(conn_info.headers, "authorization")

      assert %{"auth" => auth, "since" => "latest"} = conn_info.params
      assert Base.url_decode64!(auth, padding: false) == "Bearer tk_mytoken"

      assert :ok = ExNtfy.unsubscribe(pid)
    end
  end

  describe "frame delivery" do
    test "text frames parse to messages; open/keepalive stay internal", %{base_url: base_url} do
      pid = subscribe_ws(base_url)

      assert_receive {:ws_connected, sock, _}, 1_000
      assert_receive {:ntfy_lifecycle, ^pid, :connected}, 1_000

      push_json(sock, Fixtures.open_map())
      push_json(sock, Fixtures.full_message_map())
      push_json(sock, Fixtures.keepalive_map())

      assert_receive {:ntfy, ^pid, %Message{id: "sPs71M8A2T", event: :message}}, 1_000
      refute_received {:ntfy, ^pid, %Message{event: :open}}
      refute_received {:ntfy, ^pid, %Message{event: :keepalive}}

      push_json(sock, Fixtures.clear_response_map())

      assert_receive {:ntfy_lifecycle, ^pid,
                      {:message_clear, %Message{sequence_id: "xE73Iyuabi"}}},
                     1_000

      assert :ok = ExNtfy.unsubscribe(pid)
    end

    test "handler mode works over ws", %{base_url: base_url} do
      defmodule WSHandler do
        @behaviour ExNtfy.Handler
        @impl true
        def init(pid), do: {:ok, pid}

        @impl true
        def handle_message(message, pid) do
          send(pid, {:ws_handler, message})
          {:ok, pid}
        end
      end

      {:ok, pid} =
        Subscription.start_link(
          [
            topics: "mytopic",
            format: :ws,
            handler: {WSHandler, self()},
            base_url: base_url
          ] ++ @fast
        )

      assert_receive {:ws_connected, sock, _}, 1_000
      push_json(sock, Fixtures.full_message_map())

      assert_receive {:ws_handler, %Message{id: "sPs71M8A2T"}}, 1_000
      GenServer.stop(pid)
    end
  end

  describe "control frames and reconnect" do
    test "server pings get ponged", %{base_url: base_url} do
      pid = subscribe_ws(base_url)

      assert_receive {:ws_connected, sock, _}, 1_000
      send(sock, {:push, {:ping, "hb"}})

      assert_receive {:ws_pong, "hb"}, 1_000
      assert :ok = ExNtfy.unsubscribe(pid)
    end

    test "a rejected upgrade (non-101) is fatal", %{base_url: base_url} do
      Process.flag(:trap_exit, true)

      {:ok, pid} =
        ExNtfy.subscribe("reject-me", [base_url: base_url, format: :ws] ++ @fast)

      assert_receive {:ntfy_lifecycle, ^pid, {:down, %ExNtfy.Error{code: 40_301, http: 403}}},
                     1_000

      assert_receive {:EXIT, ^pid, {:shutdown, %ExNtfy.Error{http: 403}}}, 1_000
    end

    test "a refused connection is a transport error, not fatal HTTP" do
      Process.flag(:trap_exit, true)

      {:ok, pid} =
        ExNtfy.subscribe(
          "mytopic",
          [base_url: "http://localhost:1", format: :ws, reconnect: false] ++ @fast
        )

      assert_receive {:ntfy_lifecycle, ^pid, {:down, %ExNtfy.Error{reason: reason}}}, 1_000
      assert %Mint.TransportError{} = reason
      assert_receive {:EXIT, ^pid, {:shutdown, _reason}}, 1_000
    end

    test "a server close reconnects, resuming with since=<last id>", %{base_url: base_url} do
      pid = subscribe_ws(base_url)

      assert_receive {:ws_connected, sock, conn_info}, 1_000
      refute Map.has_key?(conn_info.params, "since")
      assert_receive {:ntfy_lifecycle, ^pid, :connected}, 1_000

      push_json(sock, Fixtures.full_message_map())
      assert_receive {:ntfy, ^pid, %Message{id: "sPs71M8A2T"}}, 1_000

      send(sock, :close)

      assert_receive {:ntfy_lifecycle, ^pid, :disconnected}, 1_000
      assert_receive {:ws_connected, _sock2, conn_info2}, 1_000
      assert conn_info2.params["since"] == "sPs71M8A2T"
      assert_receive {:ntfy_lifecycle, ^pid, :connected}, 1_000

      assert :ok = ExNtfy.unsubscribe(pid)
    end
  end
end
