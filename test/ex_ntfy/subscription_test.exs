defmodule ExNtfy.SubscriptionTest do
  use ExUnit.Case, async: true

  alias ExNtfy.{Error, Fixtures, Message, Subscription}

  @moduletag capture_log: true

  # Fast timings so reconnect/backoff tests run in milliseconds.
  @fast [reconnect_base_ms: 20, reconnect_max_ms: 100]

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, base_url: "http://localhost:#{bypass.port}"}
  end

  # Streams chunks to any connection on `path`; each connection reports
  # {:request, query_params, headers_map, server_pid} to the test, then obeys
  # {:chunk, data} / :close messages.
  #
  # trap_exit matters: when the SDK tears a connection down client-side
  # (cancel/idle-timeout/stop), cowboy exit-signals the still-blocked handler
  # with :shutdown — untrapped, Bypass records that as a failed expectation
  # and re-raises it at on_exit even though the test body passed.
  defp expect_stream(bypass, path) do
    test_pid = self()

    Bypass.expect(bypass, "GET", path, fn conn ->
      Process.flag(:trap_exit, true)
      conn = Plug.Conn.fetch_query_params(conn)
      conn = Plug.Conn.send_chunked(conn, 200)
      send(test_pid, {:request, conn.query_params, Map.new(conn.req_headers), self()})
      stream_loop(conn)
    end)
  end

  defp stream_loop(conn) do
    receive do
      {:chunk, data} ->
        case Plug.Conn.chunk(conn, data) do
          {:ok, conn} -> stream_loop(conn)
          {:error, _closed} -> conn
        end

      :close ->
        conn

      {:EXIT, _pid, _reason} ->
        # client went away — finish the plug call normally
        conn
    after
      10_000 -> conn
    end
  end

  defp json_line(map), do: JSON.encode!(map) <> "\n"

  defp subscribe(base_url, opts \\ []) do
    {:ok, pid} = ExNtfy.subscribe("mytopic", [base_url: base_url] ++ @fast ++ opts)
    pid
  end

  describe "connecting" do
    test "GETs /<topics>/json with filter/since query; open is internal, messages delivered",
         %{bypass: bypass, base_url: base_url} do
      expect_stream(bypass, "/alerts,backups/json")

      {:ok, pid} =
        ExNtfy.subscribe(
          ["alerts", "backups"],
          [base_url: base_url, since: "10m", priority: [:high, 5]] ++ @fast
        )

      assert_receive {:request, params, _headers, server}, 1_000
      assert params == %{"since" => "10m", "priority" => "4,5"}

      assert_receive {:ntfy_lifecycle, ^pid, :connected}, 1_000

      send(server, {:chunk, json_line(Fixtures.open_map())})
      send(server, {:chunk, json_line(Fixtures.full_message_map())})

      assert_receive {:ntfy, ^pid, %Message{id: "sPs71M8A2T", event: :message}}, 1_000
      refute_received {:ntfy, ^pid, %Message{event: :open}}

      assert :ok = ExNtfy.unsubscribe(pid)
    end

    test "the poll option is rejected", %{base_url: base_url} do
      assert_raise NimbleOptions.ValidationError, fn ->
        ExNtfy.subscribe("mytopic", base_url: base_url, poll: true)
      end
    end

    test "an invalid format is rejected", %{base_url: base_url} do
      assert_raise NimbleOptions.ValidationError, fn ->
        ExNtfy.subscribe("mytopic", base_url: base_url, format: :ndjson)
      end
    end

    test "an invalid handler is rejected", %{base_url: base_url} do
      assert_raise NimbleOptions.ValidationError, fn ->
        ExNtfy.subscribe("mytopic", base_url: base_url, handler: :not_a_tuple)
      end
    end

    test "poll_request/unknown events and stray process messages are ignored", %{
      bypass: bypass,
      base_url: base_url
    } do
      expect_stream(bypass, "/mytopic/json")
      pid = subscribe(base_url)

      assert_receive {:request, _, _, server}, 1_000
      assert_receive {:ntfy_lifecycle, ^pid, :connected}, 1_000

      poll_request = Map.put(Fixtures.keepalive_map(), "event", "poll_request")
      unknown = Map.put(Fixtures.keepalive_map(), "event", "brand_new_event")
      send(server, {:chunk, json_line(poll_request) <> json_line(unknown)})
      send(pid, :stray_message)

      # still alive and functional afterwards
      send(server, {:chunk, json_line(Fixtures.publish_response_map())})
      assert_receive {:ntfy, ^pid, %Message{id: "xE73Iyuabi"}}, 1_000
      refute_received {:ntfy, ^pid, %Message{event: _other}}

      assert :ok = ExNtfy.unsubscribe(pid)
    end

    test "start_link supports a name for supervision trees", %{
      bypass: bypass,
      base_url: base_url
    } do
      expect_stream(bypass, "/mytopic/json")

      {:ok, pid} =
        Subscription.start_link(
          [topics: "mytopic", name: :phase6_named_sub, base_url: base_url] ++ @fast
        )

      assert Process.whereis(:phase6_named_sub) == pid
      assert_receive {:request, _, _, _}, 1_000
      GenServer.stop(pid)
    end
  end

  describe "keepalive watchdog" do
    test "keepalives are never delivered but reset the idle watchdog", %{
      bypass: bypass,
      base_url: base_url
    } do
      expect_stream(bypass, "/mytopic/json")
      pid = subscribe(base_url, idle_timeout: 300)

      assert_receive {:request, _, _, server}, 1_000
      send(server, {:chunk, json_line(Fixtures.open_map())})
      assert_receive {:ntfy_lifecycle, ^pid, :connected}, 1_000

      for _ <- 1..4 do
        Process.sleep(150)
        send(server, {:chunk, json_line(Fixtures.keepalive_map())})
      end

      # 600 ms of keepalives at half the idle_timeout: no reconnect, nothing delivered
      refute_received {:request, _, _, _}
      refute_received {:ntfy, ^pid, _}
      refute_received {:ntfy_lifecycle, ^pid, :disconnected}

      assert :ok = ExNtfy.unsubscribe(pid)
    end

    test "idle timeout with no traffic reconnects, resuming with since=<last id>", %{
      bypass: bypass,
      base_url: base_url
    } do
      expect_stream(bypass, "/mytopic/json")
      pid = subscribe(base_url, idle_timeout: 150)

      assert_receive {:request, params, _, server}, 1_000
      refute Map.has_key?(params, "since")

      send(
        server,
        {:chunk, json_line(Fixtures.open_map()) <> json_line(Fixtures.full_message_map())}
      )

      assert_receive {:ntfy, ^pid, %Message{id: "sPs71M8A2T"}}, 1_000

      # go quiet: watchdog fires, connection is torn down and re-established
      assert_receive {:ntfy_lifecycle, ^pid, :disconnected}, 1_000
      assert_receive {:request, params2, _, _server2}, 1_000
      assert params2["since"] == "sPs71M8A2T"
      assert_receive {:ntfy_lifecycle, ^pid, :connected}, 1_000

      assert :ok = ExNtfy.unsubscribe(pid)
    end
  end

  describe "reconnecting" do
    test "a server close triggers reconnect with backoff", %{
      bypass: bypass,
      base_url: base_url
    } do
      expect_stream(bypass, "/mytopic/json")
      pid = subscribe(base_url)

      assert_receive {:request, _, _, server}, 1_000
      assert_receive {:ntfy_lifecycle, ^pid, :connected}, 1_000

      send(server, :close)

      assert_receive {:ntfy_lifecycle, ^pid, :disconnected}, 1_000
      assert_receive {:request, _, _, _}, 1_000
      assert_receive {:ntfy_lifecycle, ^pid, :connected}, 1_000

      assert :ok = ExNtfy.unsubscribe(pid)
    end

    test "a refused connection retries until the server is back", %{
      bypass: bypass,
      base_url: base_url
    } do
      expect_stream(bypass, "/mytopic/json")
      Bypass.down(bypass)

      pid = subscribe(base_url)
      Process.sleep(50)
      Bypass.up(bypass)

      assert_receive {:request, _, _, _}, 2_000
      assert_receive {:ntfy_lifecycle, ^pid, :connected}, 1_000

      assert :ok = ExNtfy.unsubscribe(pid)
    end

    test "reconnect: false delivers {:down, reason} and stops", %{
      bypass: bypass,
      base_url: base_url
    } do
      expect_stream(bypass, "/mytopic/json")
      Process.flag(:trap_exit, true)
      pid = subscribe(base_url, reconnect: false)

      assert_receive {:request, _, _, server}, 1_000
      assert_receive {:ntfy_lifecycle, ^pid, :connected}, 1_000

      send(server, :close)

      assert_receive {:ntfy_lifecycle, ^pid, :disconnected}, 1_000
      assert_receive {:ntfy_lifecycle, ^pid, {:down, _reason}}, 1_000
      assert_receive {:EXIT, ^pid, {:shutdown, _reason}}, 1_000
    end

    test "a non-2xx response is fatal even with reconnect enabled", %{
      bypass: bypass,
      base_url: base_url
    } do
      Bypass.expect_once(bypass, "GET", "/mytopic/json", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(403, JSON.encode!(%{"code" => 40_301, "http" => 403}))
      end)

      Process.flag(:trap_exit, true)
      pid = subscribe(base_url)

      assert_receive {:ntfy_lifecycle, ^pid, {:down, %Error{http: 403}}}, 1_000
      assert_receive {:EXIT, ^pid, {:shutdown, %Error{http: 403}}}, 1_000
    end
  end

  describe "lifecycle event routing" do
    test "message_clear and message_delete arrive as lifecycle events", %{
      bypass: bypass,
      base_url: base_url
    } do
      expect_stream(bypass, "/mytopic/json")
      pid = subscribe(base_url)

      assert_receive {:request, _, _, server}, 1_000

      send(server, {:chunk, json_line(Fixtures.clear_response_map())})

      assert_receive {:ntfy_lifecycle, ^pid,
                      {:message_clear, %Message{sequence_id: "xE73Iyuabi"}}},
                     1_000

      send(server, {:chunk, json_line(Fixtures.delete_response_map())})

      assert_receive {:ntfy_lifecycle, ^pid, {:message_delete, %Message{}}}, 1_000

      assert :ok = ExNtfy.unsubscribe(pid)
    end
  end

  defmodule TestHandler do
    @behaviour ExNtfy.Handler

    @impl true
    def init(test_pid) do
      send(test_pid, {:handler, :init})
      {:ok, {test_pid, 0}}
    end

    @impl true
    def handle_message(message, {test_pid, seen}) do
      send(test_pid, {:handler, :message, message, seen})
      {:ok, {test_pid, seen + 1}}
    end

    @impl true
    def handle_lifecycle(event, {test_pid, seen}) do
      send(test_pid, {:handler, :lifecycle, event, seen})
      {:ok, {test_pid, seen}}
    end
  end

  defmodule CrashHandler do
    @behaviour ExNtfy.Handler

    @impl true
    def init(test_pid), do: {:ok, test_pid}

    @impl true
    def handle_message(_message, _state), do: raise("handler boom")
  end

  describe "handler mode" do
    test "callbacks run in order with threaded state; the owner gets nothing", %{
      bypass: bypass,
      base_url: base_url
    } do
      expect_stream(bypass, "/mytopic/json")

      {:ok, pid} =
        Subscription.start_link(
          [topics: "mytopic", handler: {TestHandler, self()}, base_url: base_url] ++ @fast
        )

      assert_receive {:handler, :init}
      assert_receive {:request, _, _, server}, 1_000
      assert_receive {:handler, :lifecycle, :connected, 0}, 1_000

      send(
        server,
        {:chunk,
         json_line(Fixtures.open_map()) <>
           json_line(Fixtures.full_message_map()) <>
           json_line(Fixtures.publish_response_map())}
      )

      assert_receive {:handler, :message, %Message{id: "sPs71M8A2T"}, 0}, 1_000
      assert_receive {:handler, :message, %Message{id: "xE73Iyuabi"}, 1}, 1_000

      refute_received {:ntfy, _, _}
      refute_received {:ntfy_lifecycle, _, _}

      GenServer.stop(pid)
    end

    test "a crashing handler terminates the subscription", %{
      bypass: bypass,
      base_url: base_url
    } do
      expect_stream(bypass, "/mytopic/json")
      Process.flag(:trap_exit, true)

      {:ok, pid} =
        Subscription.start_link(
          [topics: "mytopic", handler: {CrashHandler, self()}, base_url: base_url] ++ @fast
        )

      assert_receive {:request, _, _, server}, 1_000
      send(server, {:chunk, json_line(Fixtures.full_message_map())})

      assert_receive {:EXIT, ^pid, {%RuntimeError{message: "handler boom"}, _stack}}, 1_000
    end
  end

  describe "ownership" do
    test "unsubscribe/1 stops the subscription cleanly", %{
      bypass: bypass,
      base_url: base_url
    } do
      expect_stream(bypass, "/mytopic/json")
      pid = subscribe(base_url)

      assert_receive {:request, _, _, _}, 1_000
      assert_receive {:ntfy_lifecycle, ^pid, :connected}, 1_000

      assert :ok = ExNtfy.unsubscribe(pid)
      refute Process.alive?(pid)
    end

    test "the subscription stops when its owner dies", %{
      bypass: bypass,
      base_url: base_url
    } do
      expect_stream(bypass, "/mytopic/json")
      test_pid = self()

      owner =
        spawn(fn ->
          {:ok, pid} = ExNtfy.subscribe("mytopic", [base_url: base_url] ++ @fast)
          send(test_pid, {:subscribed, pid})

          receive do
            :die -> :ok
          end
        end)

      assert_receive {:subscribed, pid}
      assert_receive {:request, _, _, _}, 1_000

      ref = Process.monitor(pid)
      send(owner, :die)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000
    end
  end

  describe "stream/2" do
    test "yields messages lazily and halts cleanly on take", %{
      bypass: bypass,
      base_url: base_url
    } do
      expect_stream(bypass, "/mytopic/json")

      task =
        Task.async(fn ->
          ExNtfy.stream("mytopic", [base_url: base_url] ++ @fast) |> Enum.take(1)
        end)

      assert_receive {:request, _, _, server}, 2_000

      send(
        server,
        {:chunk,
         json_line(Fixtures.open_map()) <>
           json_line(Fixtures.full_message_map()) <>
           json_line(Fixtures.publish_response_map())}
      )

      assert [%Message{id: "sPs71M8A2T", event: :message}] = Task.await(task)
    end
  end

  describe "other formats" do
    test "format: :sse consumes an event-stream", %{bypass: bypass, base_url: base_url} do
      expect_stream(bypass, "/mytopic/sse")
      pid = subscribe(base_url, format: :sse)

      assert_receive {:request, _, _, server}, 1_000

      send(
        server,
        {:chunk, "event: message\ndata: " <> JSON.encode!(Fixtures.full_message_map()) <> "\n\n"}
      )

      assert_receive {:ntfy, ^pid, %Message{id: "sPs71M8A2T", event: :message}}, 1_000
      assert :ok = ExNtfy.unsubscribe(pid)
    end

    test "format: :raw synthesizes body-only messages", %{bypass: bypass, base_url: base_url} do
      expect_stream(bypass, "/mytopic/raw")
      pid = subscribe(base_url, format: :raw)

      assert_receive {:request, _, _, server}, 1_000
      send(server, {:chunk, "backup done\n"})

      assert_receive {:ntfy, ^pid, %Message{event: :message, message: "backup done", id: nil}},
                     1_000

      assert :ok = ExNtfy.unsubscribe(pid)
    end
  end

  describe "auth" do
    test "token auth rides the Authorization header", %{bypass: bypass, base_url: base_url} do
      expect_stream(bypass, "/mytopic/json")
      pid = subscribe(base_url, auth: {:token, "tk_mytoken"})

      assert_receive {:request, _, headers, _}, 1_000
      assert headers["authorization"] == "Bearer tk_mytoken"

      assert :ok = ExNtfy.unsubscribe(pid)
    end

    test "auth_via: :query encodes auth into the query string", %{
      bypass: bypass,
      base_url: base_url
    } do
      expect_stream(bypass, "/mytopic/json")

      pid =
        subscribe(base_url,
          auth: {:token, "tk_mytoken"},
          auth_via: :query,
          since: :latest
        )

      assert_receive {:request, params, headers, _}, 1_000
      assert params == %{"auth" => "QmVhcmVyIHRrX215dG9rZW4", "since" => "latest"}
      refute Map.has_key?(headers, "authorization")

      assert :ok = ExNtfy.unsubscribe(pid)
    end
  end

  describe "telemetry" do
    def handle_telemetry(event, measurements, metadata, pid) do
      send(pid, {:telemetry, event, measurements, metadata})
    end

    test "connected, message, and disconnected events fire with topics metadata", %{
      bypass: bypass,
      base_url: base_url
    } do
      handler_id = "subscription-test-#{inspect(make_ref())}"

      :telemetry.attach_many(
        handler_id,
        [
          [:ex_ntfy, :subscription, :connected],
          [:ex_ntfy, :subscription, :message],
          [:ex_ntfy, :subscription, :disconnected]
        ],
        &__MODULE__.handle_telemetry/4,
        self()
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      expect_stream(bypass, "/mytopic/json")
      pid = subscribe(base_url)

      assert_receive {:request, _, _, server}, 1_000

      assert_receive {:telemetry, [:ex_ntfy, :subscription, :connected], _, %{topics: "mytopic"}},
                     1_000

      send(server, {:chunk, json_line(Fixtures.full_message_map())})

      assert_receive {:telemetry, [:ex_ntfy, :subscription, :message], _, %{topics: "mytopic"}},
                     1_000

      send(server, :close)

      assert_receive {:telemetry, [:ex_ntfy, :subscription, :disconnected], _,
                      %{topics: "mytopic"}},
                     1_000

      assert :ok = ExNtfy.unsubscribe(pid)
    end
  end
end
