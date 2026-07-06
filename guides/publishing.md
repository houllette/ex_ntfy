# Publishing cookbook

Everything ntfy can do on the publish side, one recipe at a time. All options
are validated up front — a typo raises `NimbleOptions.ValidationError` instead
of silently dropping a feature. The full option reference lives in
`ExNtfy.Publish.Options`.

## The basics

```elixir
{:ok, message} = ExNtfy.publish("mytopic", "Backup completed 🎉")
message.id    #=> "xE73Iyuabi" — keep it if you want to update/clear later
ExNtfy.publish!("mytopic", "or raise on failure")
```

## Title, priority, tags

```elixir
ExNtfy.publish("alerts", "Disk almost full",
  title: "Server alert",
  priority: :urgent,             # 1..5 or :min | :low | :default | :high | :max | :urgent
  tags: [:warning, "disk-42"]    # emoji shortcodes render as emoji
)
```

## Markdown, click URLs, icons

```elixir
ExNtfy.publish("deploys", "Deploy finished **successfully**",
  markdown: true,
  click: "https://example.com/deploys/42",
  icon: "https://example.com/icon.png"
)
```

## Action buttons (up to 3)

```elixir
alias ExNtfy.Action

ExNtfy.publish("garage", "Door open for 15 minutes",
  actions: [
    %Action{type: :view, label: "Camera", url: "https://cam.example.com", clear: true},
    %Action{type: :http, label: "Close door", url: "https://api.example.com/door",
            method: "PUT", body: ~s({"action":"close"})},
    %Action{type: :broadcast, label: "Take picture", extras: %{"cmd" => "pic"}}
  ]
)
```

`:view` opens a URL, `:http` fires a request, `:broadcast` sends an Android
broadcast, `:copy` copies a value. Plain ntfy-shaped maps and raw JSON strings
are also accepted.

## Scheduled delivery

```elixir
ExNtfy.publish("reminders", "Standup!", delay: "30m")
ExNtfy.publish("reminders", "Happy new year", delay: ~U[2027-01-01 00:00:00Z])
ExNtfy.publish("reminders", "Lunch", delay: "tomorrow, 12pm")
```

## E-mail and phone-call forwarding

```elixir
ExNtfy.publish("alerts", "Server down", email: "ops@example.com")
ExNtfy.publish("alerts", "Server REALLY down", call: true)  # verified number
```

## Attachments

By URL (the server never downloads it — clients do):

```elixir
ExNtfy.publish("mytopic", "Check this out",
  attach: "https://example.com/build.log", filename: "build.log")
```

By upload — iodata, a stream of chunks, or `{:file, path}` (streamed from
disk; filename defaults to the basename):

```elixir
{:ok, message} =
  ExNtfy.publish_file("mytopic", {:file, "/tmp/flower.jpg"},
    message: "Look what I found")

message.attachment.url  #=> "https://ntfy.sh/file/..."
```

ntfy.sh caps uploads (~2 MB); an oversized file returns
`{:error, %ExNtfy.Error{http: 413}}`.

## Notification lifecycle: update, clear, delete

Messages sharing a sequence ID form a sequence; clients show the latest state.
The simplest idiom reuses the returned `id`:

```elixir
{:ok, msg} = ExNtfy.publish("deploys", "Deploy started…")
ExNtfy.update("deploys", msg.id, "Deploy at 80%…")
ExNtfy.update("deploys", msg.id, "Deploy finished ✅")
ExNtfy.clear("deploys", msg.id)    # mark read + dismiss on all clients
ExNtfy.delete("deploys", msg.id)   # remove from clients entirely
```

Or pick your own sequence ID up front:
`ExNtfy.publish("deploys", "…", sequence_id: "deploy-42")`.

## Templates: forward webhook payloads

`publish_raw/3` sends the body byte-identical with options as headers — the
path for handing ntfy a JSON webhook payload to render server-side:

```elixir
# pre-defined templates
ExNtfy.publish_raw("builds", github_webhook_json, template: :github)

# inline Go templates evaluated against the body
ExNtfy.publish_raw("builds", payload_json,
  template: true,
  title: "CI result",
  message: "Build {{.status}} ({{.commit}})"
)
```

## Webhook-style GET

Everything in the query string — handy for curl one-liners and systems that
can only fire GETs:

```elixir
ExNtfy.trigger("mytopic", message: "cron ran", tags: [:clock])
```

## Header-only switches

```elixir
ExNtfy.publish("mytopic", "ephemeral", cache: false)      # live subscribers only
ExNtfy.publish("mytopic", "no FCM", firebase: false)      # ntfy connections only
ExNtfy.publish("up-app-topic", "wake up", unified_push: true)
```

## Telemetry

Every publish emits `[:ex_ntfy, :publish, :start | :stop | :exception]` span
events with `%{topic, base_url}` metadata — never credentials or contents.
