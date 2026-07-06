defmodule ExNtfy.PublisherTest do
  use ExUnit.Case, async: true

  import ExNtfy.TestHelpers

  alias ExNtfy.{Action, Attachment, Error, Fixtures, Message}

  describe "publish/3" do
    test "POSTs a minimal JSON body to / and parses the created message" do
      opts =
        req_stub(fn conn ->
          assert conn.method == "POST"
          assert conn.request_path == "/"
          assert Plug.Conn.get_req_header(conn, "content-type") == ["application/json"]

          {:ok, body, conn} = Plug.Conn.read_body(conn)
          assert JSON.decode!(body) == %{"topic" => "mytopic", "message" => "hi"}

          Req.Test.json(conn, Fixtures.publish_response_map())
        end)

      assert {:ok, %Message{} = message} = ExNtfy.publish("mytopic", "hi", opts)
      assert message.id == "xE73Iyuabi"
      assert message.time == 1_673_542_291
      assert message.event == :message
      assert message.topic == "mytopic"
    end

    test "kitchen sink: every JSON option lands in the body, header-only options as headers" do
      actions = [
        %Action{
          type: :view,
          label: "Open portal",
          url: "https://example.com/deploys/42",
          clear: true
        },
        %{
          "action" => "http",
          "label" => "Close door",
          "url" => "https://api.example.com/door",
          "method" => "PUT"
        }
      ]

      opts =
        [
          title: "Deploy status",
          priority: :high,
          tags: [:tada, "deploy"],
          markdown: true,
          delay: "30m",
          click: "https://example.com/deploys/42",
          icon: "https://example.com/icon.png",
          attach: "https://example.com/build.log",
          filename: "build.log",
          actions: actions,
          email: "ops@example.com",
          call: true,
          sequence_id: "deploy-42",
          cache: false,
          firebase: false,
          unified_push: true,
          template: :github,
          poll_id: "p1"
        ] ++
          req_stub(fn conn ->
            assert Plug.Conn.get_req_header(conn, "x-cache") == ["no"]
            assert Plug.Conn.get_req_header(conn, "x-firebase") == ["no"]
            assert Plug.Conn.get_req_header(conn, "x-unifiedpush") == ["1"]
            assert Plug.Conn.get_req_header(conn, "x-template") == ["github"]
            assert Plug.Conn.get_req_header(conn, "x-poll-id") == ["p1"]

            {:ok, body, conn} = Plug.Conn.read_body(conn)
            decoded = JSON.decode!(body)

            assert decoded == %{
                     "topic" => "mytopic",
                     "message" => "Deploy finished **successfully**",
                     "title" => "Deploy status",
                     "priority" => 4,
                     "tags" => ["tada", "deploy"],
                     "markdown" => true,
                     "delay" => "30m",
                     "click" => "https://example.com/deploys/42",
                     "icon" => "https://example.com/icon.png",
                     "attach" => "https://example.com/build.log",
                     "filename" => "build.log",
                     "actions" => [
                       %{
                         "action" => "view",
                         "label" => "Open portal",
                         "url" => "https://example.com/deploys/42",
                         "clear" => true
                       },
                       %{
                         "action" => "http",
                         "label" => "Close door",
                         "url" => "https://api.example.com/door",
                         "method" => "PUT"
                       }
                     ],
                     "email" => "ops@example.com",
                     "call" => "yes",
                     "sequence_id" => "deploy-42"
                   }

            refute Map.has_key?(decoded, "cache")
            refute Map.has_key?(decoded, "firebase")
            refute Map.has_key?(decoded, "unified_push")
            refute Map.has_key?(decoded, "template")
            refute Map.has_key?(decoded, "poll_id")

            Req.Test.json(conn, Fixtures.publish_response_map())
          end)

      assert {:ok, %Message{}} =
               ExNtfy.publish("mytopic", "Deploy finished **successfully**", opts)
    end

    test "a nil message publishes options only" do
      opts =
        req_stub(fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          assert JSON.decode!(body) == %{"topic" => "mytopic", "title" => "Ping"}
          Req.Test.json(conn, Fixtures.publish_response_map())
        end)

      assert {:ok, %Message{}} = ExNtfy.publish("mytopic", nil, [title: "Ping"] ++ opts)
    end

    test "unknown options raise before any request is made" do
      assert_raise NimbleOptions.ValidationError, fn ->
        ExNtfy.publish("mytopic", "hi", titel: "typo")
      end
    end

    test "a 429 becomes {:error, %Error{}} with the ntfy fields" do
      opts =
        req_stub(fn conn ->
          conn
          |> Plug.Conn.put_status(429)
          |> Req.Test.json(Fixtures.error_429_map())
        end)

      assert {:error, %Error{code: 42_901, http: 429} = error} =
               ExNtfy.publish("mytopic", "hi", opts)

      assert error.error =~ "limit reached"
    end

    test "a transport error becomes {:error, %Error{reason: ...}}" do
      opts = req_stub(fn conn -> Req.Test.transport_error(conn, :timeout) end)

      assert {:error, %Error{reason: %Req.TransportError{reason: :timeout}}} =
               ExNtfy.publish("mytopic", "hi", [retry: false] ++ opts)
    end

    test "a 2xx body that is not a message becomes an :invalid_response error" do
      opts = req_stub(fn conn -> Req.Test.json(conn, %{"ok" => true}) end)

      assert {:error, %Error{reason: {:invalid_response, {:missing_fields, _}}}} =
               ExNtfy.publish("mytopic", "hi", opts)
    end
  end

  describe "publish!/3" do
    test "returns the message directly on success" do
      opts = req_stub(fn conn -> Req.Test.json(conn, Fixtures.publish_response_map()) end)

      assert %Message{id: "xE73Iyuabi"} = ExNtfy.publish!("mytopic", "hi", opts)
    end

    test "raises ExNtfy.Error on failure" do
      opts =
        req_stub(fn conn ->
          conn
          |> Plug.Conn.put_status(429)
          |> Req.Test.json(Fixtures.error_429_map())
        end)

      error =
        assert_raise Error, fn ->
          ExNtfy.publish!("mytopic", "hi", opts)
        end

      assert error.code == 42_901
      assert Exception.message(error) =~ "42901"
    end
  end

  describe "publish_raw/3" do
    test "POSTs the body to /<topic> byte-identical, options as headers" do
      raw = <<"raw bytes", 0, 255, 254>>

      opts =
        req_stub(fn conn ->
          assert conn.method == "POST"
          assert conn.request_path == "/mytopic"
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          assert body == raw
          assert Plug.Conn.get_req_header(conn, "x-filename") == ["dump.bin"]
          Req.Test.json(conn, Fixtures.publish_response_map())
        end)

      assert {:ok, %Message{}} =
               ExNtfy.publish_raw("mytopic", raw, [filename: "dump.bin"] ++ opts)
    end

    test "a UTF-8 title goes out RFC 2047-encoded" do
      opts =
        req_stub(fn conn ->
          assert Plug.Conn.get_req_header(conn, "x-title") == ["=?UTF-8?B?R3LDvMOfZSDwn5GL?="]
          Req.Test.json(conn, Fixtures.publish_response_map())
        end)

      assert {:ok, %Message{}} =
               ExNtfy.publish_raw("mytopic", "body", [title: "Grüße 👋"] ++ opts)
    end

    test "inline templating: JSON webhook body with template message and title" do
      webhook = JSON.encode!(%{"status" => "success", "commit" => "abc123"})

      opts =
        req_stub(fn conn ->
          assert conn.method == "POST"
          assert conn.request_path == "/mytopic"

          assert Plug.Conn.get_req_header(conn, "x-template") == ["yes"]

          assert Plug.Conn.get_req_header(conn, "x-message") == [
                   "Build {{.status}} ({{.commit}})"
                 ]

          assert Plug.Conn.get_req_header(conn, "x-title") == ["CI result"]

          {:ok, body, conn} = Plug.Conn.read_body(conn)
          assert body == webhook

          Req.Test.json(conn, Fixtures.publish_response_map())
        end)

      assert {:ok, %Message{}} =
               ExNtfy.publish_raw(
                 "mytopic",
                 webhook,
                 [
                   template: true,
                   message: "Build {{.status}} ({{.commit}})",
                   title: "CI result"
                 ] ++ opts
               )
    end
  end

  describe "trigger/2" do
    test "GETs /<topic>/trigger with options only in the query string and no body" do
      opts =
        req_stub(fn conn ->
          assert conn.method == "GET"
          assert conn.request_path == "/mytopic/trigger"

          conn = Plug.Conn.fetch_query_params(conn)

          assert conn.query_params == %{
                   "title" => "Backup done",
                   "tags" => "warning,backup",
                   "priority" => "5"
                 }

          {:ok, body, conn} = Plug.Conn.read_body(conn)
          assert body == ""

          Req.Test.json(conn, Fixtures.publish_response_map())
        end)

      assert {:ok, %Message{}} =
               ExNtfy.trigger(
                 "mytopic",
                 [title: "Backup done", tags: [:warning, "backup"], priority: 5] ++ opts
               )
    end
  end

  describe "publish_file/3" do
    test "PUTs iodata to /<topic> byte-identical with X-Filename" do
      opts =
        req_stub(fn conn ->
          assert conn.method == "PUT"
          assert conn.request_path == "/mytopic"
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          assert body == "chunk1chunk2"
          assert Plug.Conn.get_req_header(conn, "x-filename") == ["data.bin"]
          Req.Test.json(conn, Fixtures.upload_response_map())
        end)

      assert {:ok, %Message{}} =
               ExNtfy.publish_file(
                 "mytopic",
                 ["chunk1", "chunk2"],
                 [filename: "data.bin"] ++ opts
               )
    end

    @tag :tmp_dir
    test "{:file, path} streams the file; filename defaults to the basename", %{
      tmp_dir: tmp_dir
    } do
      path = Path.join(tmp_dir, "flower.jpg")
      content = :crypto.strong_rand_bytes(200_000)
      File.write!(path, content)

      opts =
        req_stub(fn conn ->
          assert conn.method == "PUT"
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          assert body == content
          assert Plug.Conn.get_req_header(conn, "x-filename") == ["flower.jpg"]
          Req.Test.json(conn, Fixtures.upload_response_map())
        end)

      assert {:ok, %Message{}} = ExNtfy.publish_file("mytopic", {:file, path}, opts)
    end

    @tag :tmp_dir
    test "an explicit :filename overrides the {:file, path} basename", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "upload.tmp")
      File.write!(path, "data")

      opts =
        req_stub(fn conn ->
          assert Plug.Conn.get_req_header(conn, "x-filename") == ["report.pdf"]
          Req.Test.json(conn, Fixtures.upload_response_map())
        end)

      assert {:ok, %Message{}} =
               ExNtfy.publish_file("mytopic", {:file, path}, [filename: "report.pdf"] ++ opts)
    end

    test "Phase-3 options ride along as headers" do
      opts =
        req_stub(fn conn ->
          assert Plug.Conn.get_req_header(conn, "x-title") == ["=?UTF-8?B?R3LDvMOfZSDwn5GL?="]
          assert Plug.Conn.get_req_header(conn, "x-message") == ["Here is the report"]
          assert Plug.Conn.get_req_header(conn, "x-priority") == ["5"]
          assert Plug.Conn.get_req_header(conn, "x-delay") == ["30m"]
          Req.Test.json(conn, Fixtures.upload_response_map())
        end)

      assert {:ok, %Message{}} =
               ExNtfy.publish_file(
                 "mytopic",
                 "bytes",
                 [
                   title: "Grüße 👋",
                   message: "Here is the report",
                   priority: :urgent,
                   delay: "30m"
                 ] ++ opts
               )
    end

    test "the upload response parses a fully populated attachment" do
      opts = req_stub(fn conn -> Req.Test.json(conn, Fixtures.upload_response_map()) end)

      assert {:ok, %Message{attachment: %Attachment{} = attachment}} =
               ExNtfy.publish_file("mytopic", "bytes", opts)

      assert attachment.name == "flower.jpg"
      assert attachment.url == "https://ntfy.sh/file/oaFAdEY1KC.jpg"
      assert attachment.type == "image/jpeg"
      assert attachment.size == 12_345
      assert attachment.expires == 1_735_963_200
    end

    test "a 413 (attachment too large) maps to %Error{}" do
      opts =
        req_stub(fn conn ->
          conn
          |> Plug.Conn.put_status(413)
          |> Req.Test.json(%{
            "code" => 41_301,
            "http" => 413,
            "error" => "attachment too large"
          })
        end)

      assert {:error, %Error{code: 41_301, http: 413, error: "attachment too large"}} =
               ExNtfy.publish_file("mytopic", "bytes", opts)
    end

    test "publish_file!/3 returns the message and raises on failure" do
      ok_opts = req_stub(fn conn -> Req.Test.json(conn, Fixtures.upload_response_map()) end)
      assert %Message{id: "0d5SgUWXH2"} = ExNtfy.publish_file!("mytopic", "bytes", ok_opts)

      error_opts =
        req_stub(fn conn ->
          conn
          |> Plug.Conn.put_status(429)
          |> Req.Test.json(Fixtures.error_429_map())
        end)

      assert_raise Error, fn -> ExNtfy.publish_file!("mytopic", "bytes", error_opts) end
    end
  end

  describe "update/4" do
    test "publishes with sequence_id in the JSON body; the response carries it" do
      opts =
        req_stub(fn conn ->
          assert conn.method == "POST"
          assert conn.request_path == "/"
          {:ok, body, conn} = Plug.Conn.read_body(conn)

          assert JSON.decode!(body) == %{
                   "topic" => "mytopic",
                   "message" => "Deploy at 80%",
                   "sequence_id" => "xE73Iyuabi",
                   "priority" => 3
                 }

          Req.Test.json(
            conn,
            Map.put(Fixtures.publish_response_map(), "sequence_id", "xE73Iyuabi")
          )
        end)

      assert {:ok, %Message{sequence_id: "xE73Iyuabi"}} =
               ExNtfy.update("mytopic", "xE73Iyuabi", "Deploy at 80%", [priority: 3] ++ opts)
    end
  end

  describe "clear/3" do
    test "PUTs /<topic>/<seq>/clear with no body" do
      opts =
        req_stub(fn conn ->
          assert conn.method == "PUT"
          assert conn.request_path == "/mytopic/xE73Iyuabi/clear"
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          assert body == ""
          Req.Test.json(conn, Fixtures.clear_response_map())
        end)

      assert {:ok, %Message{event: :message_clear, sequence_id: "xE73Iyuabi"}} =
               ExNtfy.clear("mytopic", "xE73Iyuabi", opts)
    end

    test "a 429 maps to %Error{}" do
      opts =
        req_stub(fn conn ->
          conn
          |> Plug.Conn.put_status(429)
          |> Req.Test.json(Fixtures.error_429_map())
        end)

      assert {:error, %Error{code: 42_901, http: 429}} =
               ExNtfy.clear("mytopic", "xE73Iyuabi", opts)
    end
  end

  describe "delete/3" do
    test "sends DELETE /<topic>/<seq>" do
      opts =
        req_stub(fn conn ->
          assert conn.method == "DELETE"
          assert conn.request_path == "/mytopic/xE73Iyuabi"
          Req.Test.json(conn, Fixtures.delete_response_map())
        end)

      assert {:ok, %Message{event: :message_delete, sequence_id: "xE73Iyuabi"}} =
               ExNtfy.delete("mytopic", "xE73Iyuabi", opts)
    end
  end

  describe "path escaping" do
    test "sequence IDs with URL-meaningful characters are escaped" do
      opts =
        req_stub(fn conn ->
          assert conn.request_path == "/mytopic/seq%20id%2F%3Fx/clear"
          Req.Test.json(conn, Fixtures.clear_response_map())
        end)

      assert {:ok, %Message{}} = ExNtfy.clear("mytopic", "seq id/?x", opts)
    end

    test "topic names are escaped everywhere" do
      opts =
        req_stub(fn conn ->
          assert conn.request_path == "/my%20topic"
          Req.Test.json(conn, Fixtures.publish_response_map())
        end)

      assert {:ok, %Message{}} = ExNtfy.publish_raw("my topic", "body", opts)
    end
  end

  describe "telemetry" do
    def handle_telemetry(event, measurements, metadata, pid) do
      send(pid, {:telemetry, event, measurements, metadata})
    end

    test "publish emits start and stop events with topic metadata" do
      handler_id = "publisher-test-#{inspect(make_ref())}"

      :telemetry.attach_many(
        handler_id,
        [[:ex_ntfy, :publish, :start], [:ex_ntfy, :publish, :stop]],
        &__MODULE__.handle_telemetry/4,
        self()
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      opts = req_stub(fn conn -> Req.Test.json(conn, Fixtures.publish_response_map()) end)
      assert {:ok, %Message{}} = ExNtfy.publish("mytopic", "hi", opts)

      assert_received {:telemetry, [:ex_ntfy, :publish, :start], %{system_time: _},
                       %{topic: "mytopic", base_url: "https://ntfy.sh"}}

      assert_received {:telemetry, [:ex_ntfy, :publish, :stop], %{duration: _},
                       %{topic: "mytopic", base_url: "https://ntfy.sh"}}
    end
  end
end
