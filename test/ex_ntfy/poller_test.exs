defmodule ExNtfy.PollerTest do
  use ExUnit.Case, async: true

  import ExNtfy.TestHelpers
  import ExUnit.CaptureLog

  alias ExNtfy.{Error, Fixtures, Message}

  defp ndjson(conn, maps_or_lines) do
    body =
      Enum.map_join(maps_or_lines, "\n", fn
        line when is_binary(line) -> line
        map -> JSON.encode!(map)
      end)

    conn
    |> Plug.Conn.put_resp_content_type("application/x-ndjson")
    |> Plug.Conn.resp(200, body)
  end

  describe "poll/2 request shape" do
    test "GETs /<topics>/json with poll=1 and encoded options" do
      opts =
        req_stub(fn conn ->
          assert conn.method == "GET"
          assert conn.request_path == "/alerts,backups/json"

          conn = Plug.Conn.fetch_query_params(conn)

          assert conn.query_params == %{
                   "poll" => "1",
                   "since" => "10m",
                   "scheduled" => "1"
                 }

          ndjson(conn, [])
        end)

      assert {:ok, []} =
               ExNtfy.poll(["alerts", "backups"], [since: "10m", scheduled: true] ++ opts)
    end

    test "filter params land verbatim in the query" do
      opts =
        req_stub(fn conn ->
          conn = Plug.Conn.fetch_query_params(conn)

          assert conn.query_params == %{
                   "poll" => "1",
                   "id" => "xE73Iyuabi",
                   "message" => "exact body",
                   "title" => "exact title",
                   "priority" => "4,5",
                   "tags" => "warning,backup"
                 }

          ndjson(conn, [])
        end)

      assert {:ok, []} =
               ExNtfy.poll(
                 "mytopic",
                 [
                   id: "xE73Iyuabi",
                   message: "exact body",
                   title: "exact title",
                   priority: [:high, 5],
                   tags: [:warning, "backup"]
                 ] ++ opts
               )
    end

    test "unknown options raise before any request" do
      assert_raise NimbleOptions.ValidationError, fn ->
        ExNtfy.poll("mytopic", sched: true)
      end
    end
  end

  describe "poll/2 response parsing" do
    test "parses ndjson lines into ordered messages, dropping open/keepalive" do
      opts =
        req_stub(fn conn ->
          ndjson(conn, [
            Fixtures.open_map(),
            Fixtures.full_message_map(),
            Fixtures.keepalive_map(),
            Fixtures.publish_response_map()
          ])
        end)

      assert {:ok, [first, second]} = ExNtfy.poll("mytopic", opts)
      assert %Message{id: "sPs71M8A2T", event: :message} = first
      assert %Message{id: "xE73Iyuabi", event: :message} = second
    end

    test "an empty body yields an empty list" do
      opts = req_stub(fn conn -> ndjson(conn, []) end)
      assert {:ok, []} = ExNtfy.poll("mytopic", opts)
    end

    test "trailing blank lines don't crash" do
      opts =
        req_stub(fn conn ->
          ndjson(conn, [Fixtures.publish_response_map(), "", ""])
        end)

      assert {:ok, [%Message{id: "xE73Iyuabi"}]} = ExNtfy.poll("mytopic", opts)
    end

    test "a malformed line is skipped with a warning, keeping the rest" do
      opts =
        req_stub(fn conn ->
          ndjson(conn, [
            Fixtures.full_message_map(),
            "this is not json {",
            Fixtures.publish_response_map()
          ])
        end)

      {result, log} = with_log(fn -> ExNtfy.poll("mytopic", opts) end)

      assert {:ok, [%Message{id: "sPs71M8A2T"}, %Message{id: "xE73Iyuabi"}]} = result
      assert log =~ "skipping"
    end

    test "a 2xx body that is not ndjson becomes an :invalid_response error" do
      opts = req_stub(fn conn -> Req.Test.json(conn, %{"unexpected" => "object"}) end)

      assert {:error, %Error{reason: {:invalid_response, %{"unexpected" => "object"}}}} =
               ExNtfy.poll("mytopic", opts)
    end
  end

  describe "poll/2 auth" do
    test "token auth rides the Authorization header" do
      opts =
        req_stub(fn conn ->
          assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer tk_mytoken"]
          ndjson(conn, [])
        end)

      assert {:ok, []} = ExNtfy.poll("mytopic", [auth: {:token, "tk_mytoken"}] ++ opts)
    end

    test "auth_via: :query merges the auth param with the poll params" do
      opts =
        req_stub(fn conn ->
          conn = Plug.Conn.fetch_query_params(conn)

          assert conn.query_params == %{
                   "poll" => "1",
                   "since" => "latest",
                   "auth" => "QmVhcmVyIHRrX215dG9rZW4"
                 }

          ndjson(conn, [])
        end)

      assert {:ok, []} =
               ExNtfy.poll(
                 "mytopic",
                 [auth: {:token, "tk_mytoken"}, auth_via: :query, since: :latest] ++ opts
               )
    end
  end

  describe "poll/2 error paths" do
    test "a 404 maps to %Error{}" do
      opts =
        req_stub(fn conn ->
          conn
          |> Plug.Conn.put_status(404)
          |> Req.Test.json(%{"code" => 40_401, "http" => 404, "error" => "page not found"})
        end)

      assert {:error, %Error{code: 40_401, http: 404}} = ExNtfy.poll("mytopic", opts)
    end

    test "a 403 maps to %Error{}" do
      opts =
        req_stub(fn conn ->
          conn
          |> Plug.Conn.put_status(403)
          |> Req.Test.json(%{"code" => 40_301, "http" => 403, "error" => "forbidden"})
        end)

      assert {:error, %Error{code: 40_301, http: 403, error: "forbidden"}} =
               ExNtfy.poll("mytopic", opts)
    end
  end

  describe "poll!/2" do
    test "returns the message list directly" do
      opts = req_stub(fn conn -> ndjson(conn, [Fixtures.publish_response_map()]) end)
      assert [%Message{id: "xE73Iyuabi"}] = ExNtfy.poll!("mytopic", opts)
    end

    test "raises ExNtfy.Error on failure" do
      opts =
        req_stub(fn conn ->
          conn
          |> Plug.Conn.put_status(403)
          |> Req.Test.json(%{"code" => 40_301, "http" => 403, "error" => "forbidden"})
        end)

      assert_raise Error, fn -> ExNtfy.poll!("mytopic", opts) end
    end
  end

  describe "telemetry" do
    def handle_telemetry(event, measurements, metadata, pid) do
      send(pid, {:telemetry, event, measurements, metadata})
    end

    test "poll emits start and stop events with topics metadata" do
      handler_id = "poller-test-#{inspect(make_ref())}"

      :telemetry.attach_many(
        handler_id,
        [[:ex_ntfy, :poll, :start], [:ex_ntfy, :poll, :stop]],
        &__MODULE__.handle_telemetry/4,
        self()
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      opts = req_stub(fn conn -> ndjson(conn, []) end)
      assert {:ok, []} = ExNtfy.poll(["a", "b"], opts)

      assert_received {:telemetry, [:ex_ntfy, :poll, :start], %{system_time: _},
                       %{topics: ["a", "b"], base_url: "https://ntfy.sh"}}

      assert_received {:telemetry, [:ex_ntfy, :poll, :stop], %{duration: _},
                       %{topics: ["a", "b"], base_url: "https://ntfy.sh"}}
    end
  end
end
