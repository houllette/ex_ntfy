# ExNtfy

[![CI](https://github.com/houllette/ex_ntfy/actions/workflows/ci.yml/badge.svg)](https://github.com/houllette/ex_ntfy/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/ex_ntfy.svg)](https://hex.pm/packages/ex_ntfy)
[![Documentation](https://img.shields.io/badge/hexdocs-ex__ntfy-purple.svg)](https://hexdocs.pm/ex_ntfy)

An Elixir SDK for [ntfy](https://ntfy.sh) — the simple HTTP-based pub-sub
notification service. Publish notifications to any topic and subscribe to
them, on ntfy.sh or your self-hosted server. Built on
[Req](https://hexdocs.pm/req), tested against the real API.

## Installation

```elixir
def deps do
  [
    {:ex_ntfy, "~> 0.1.0"},
    # optional — only for WebSocket subscriptions (format: :ws)
    {:mint_web_socket, "~> 1.0"}
  ]
end
```

## Publish

```elixir
# a topic is all you need — no signup
{:ok, message} = ExNtfy.publish("mytopic", "Backup completed 🎉")

# full option surface: title, priority, tags, actions, delay, attachments, ...
ExNtfy.publish("alerts", "Disk almost full",
  title: "Server alert",
  priority: :urgent,
  tags: [:warning, :floppy_disk],
  click: "https://grafana.example.com/d/disk",
  actions: [
    %ExNtfy.Action{type: :view, label: "Open dashboard", url: "https://grafana.example.com"}
  ]
)

# upload a file as an attachment (streamed from disk)
ExNtfy.publish_file("mytopic", {:file, "/tmp/report.pdf"}, message: "Monthly report")

# update / dismiss / delete a delivered notification later
{:ok, msg} = ExNtfy.publish("deploys", "Deploy started…")
ExNtfy.update("deploys", msg.id, "Deploy finished ✅")
ExNtfy.clear("deploys", msg.id)
```

See the [Publishing cookbook](https://hexdocs.pm/ex_ntfy/publishing.html) for
every option, including templates, scheduled delivery, e-mail forwarding, and
webhook-style `ExNtfy.trigger/2`.

## Poll

Fetch cached messages one-shot, with the full `since`/filter surface:

```elixir
{:ok, messages} = ExNtfy.poll("mytopic", since: "10m")
{:ok, urgent} = ExNtfy.poll(["alerts", "backups"], priority: [:high, :urgent])
```

## Subscribe

Long-lived subscriptions reconnect automatically (resuming from the last seen
message) and watch for dead connections. Pick a consumption style:

```elixir
# 1. messages to your process
{:ok, sub} = ExNtfy.subscribe("alerts")
receive do
  {:ntfy, ^sub, %ExNtfy.Message{} = message} -> IO.puts(message.message)
end

# 2. a handler in your supervision tree
defmodule MyApp.NtfyHandler do
  @behaviour ExNtfy.Handler
  @impl true
  def init(arg), do: {:ok, arg}
  @impl true
  def handle_message(message, state) do
    MyApp.Alerts.process(message)
    {:ok, state}
  end
end

children = [
  {ExNtfy.Subscription, topics: "alerts", handler: {MyApp.NtfyHandler, []}}
]

# 3. a lazy stream
ExNtfy.stream("alerts") |> Stream.filter(&(&1.priority >= 4)) |> Enum.take(5)
```

The [Subscriptions guide](https://hexdocs.pm/ex_ntfy/subscriptions.html)
covers lifecycle events, reconnect semantics, and the `:sse`/`:raw`/`:ws`
transports.

## Authentication & self-hosted servers

Every function takes client options; app-wide defaults go in config:

```elixir
# per call
ExNtfy.publish("private", "hi",
  base_url: "https://ntfy.example.com",
  auth: {:token, "tk_..."}          # or {:basic, "user", "pass"}
)

# config/runtime.exs
config :ex_ntfy,
  base_url: "https://ntfy.example.com",
  auth: {:token, System.fetch_env!("NTFY_TOKEN")}
```

For clients that can't set headers, `auth_via: :query` sends credentials as
the `?auth=` parameter instead.

## Documentation

Full API reference and guides: <https://hexdocs.pm/ex_ntfy>.

## License

[MIT](https://github.com/houllette/ex_ntfy/blob/main/LICENSE)
