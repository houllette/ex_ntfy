# Testing your app

How to test code that calls ExNtfy without hitting a real ntfy server.

## Stub the HTTP layer with Req.Test

Every ExNtfy function accepts client options, and `req_options:` is merged
into the underlying [Req](https://hexdocs.pm/req) request last — so you can
inject a [`Req.Test`](https://hexdocs.pm/req/Req.Test.html) plug exactly like
ExNtfy's own suite does:

```elixir
defmodule MyApp.AlertsTest do
  use ExUnit.Case, async: true

  test "publishes a disk alert" do
    Req.Test.stub(MyApp.NtfyStub, fn conn ->
      assert conn.method == "POST"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = JSON.decode!(body)
      assert decoded["topic"] == "alerts"
      assert decoded["priority"] == 5

      Req.Test.json(conn, %{
        "id" => "xE73Iyuabi",
        "time" => 1_673_542_291,
        "event" => "message",
        "topic" => "alerts",
        "message" => decoded["message"]
      })
    end)

    opts = [req_options: [plug: {Req.Test, MyApp.NtfyStub}]]

    assert {:ok, message} = MyApp.Alerts.disk_full("db-01", opts)
    assert message.id == "xE73Iyuabi"
  end
end
```

A practical pattern: have your wrapper module accept options and default them
from config, so tests inject the plug and production injects nothing:

```elixir
defmodule MyApp.Alerts do
  def disk_full(host, opts \\ []) do
    ExNtfy.publish("alerts", "Disk almost full on #{host}",
      [priority: :urgent] ++ opts ++ Application.get_env(:my_app, :ntfy_opts, [])
    )
  end
end
```

## Simulating failures

```elixir
# ntfy error responses
Req.Test.stub(MyApp.NtfyStub, fn conn ->
  conn
  |> Plug.Conn.put_status(429)
  |> Req.Test.json(%{"code" => 42_901, "http" => 429, "error" => "limit reached"})
end)

# transport errors (pass retry: false to skip Req's transient retries)
Req.Test.stub(MyApp.NtfyStub, fn conn ->
  Req.Test.transport_error(conn, :timeout)
end)
```

Both surface as `{:error, %ExNtfy.Error{}}` — the first with `code`/`http`
set, the second with the exception in `reason`.

## Polling works the same way

Poll responses are ndjson — one JSON object per line:

```elixir
Req.Test.stub(MyApp.NtfyStub, fn conn ->
  body =
    [%{"id" => "a1", "time" => 1, "event" => "message", "topic" => "t", "message" => "hi"}]
    |> Enum.map_join("\n", &JSON.encode!/1)

  conn
  |> Plug.Conn.put_resp_content_type("application/x-ndjson")
  |> Plug.Conn.resp(200, body)
end)
```

## Streaming subscriptions

`Req.Test` plugs can't exercise long-lived chunked connections — for
subscription behavior you need a real server in the test, e.g.
[Bypass](https://hexdocs.pm/bypass) with `Plug.Conn.send_chunked/2`. In
practice you rarely need that: put your logic in an `ExNtfy.Handler` (or the
process receiving `{:ntfy, pid, message}`) and unit-test it by calling the
callbacks directly with `%ExNtfy.Message{}` structs — the reconnect/delivery
machinery is ExNtfy's responsibility and is covered by its own suite.

If you do want end-to-end subscription tests, ExNtfy's repository is the
reference: `test/ex_ntfy/subscription_test.exs` shows the Bypass streaming
setup, including the exit-trapping its handlers need.
