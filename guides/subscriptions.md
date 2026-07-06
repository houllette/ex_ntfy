# Subscriptions

Receiving messages, from one-shot polls to supervised streaming subscriptions.

## Polling: one-shot fetches

`ExNtfy.poll/2` returns cached messages and closes the connection — no
processes involved. Full filter surface in `ExNtfy.Subscribe.Options`:

```elixir
{:ok, messages} = ExNtfy.poll("mytopic")                       # everything cached
{:ok, messages} = ExNtfy.poll(["alerts", "backups"], since: "10m")
{:ok, messages} = ExNtfy.poll("mytopic", since: last_seen.id)  # resume by message id
{:ok, urgent} = ExNtfy.poll("mytopic", priority: [:high, :urgent], tags: [:prod])
```

`priority:` filters match **any** listed value (OR); `tags:` must **all**
match (AND). `scheduled: true` includes not-yet-delivered scheduled messages.

## Streaming subscriptions

`ExNtfy.Subscription` holds one connection open and:

  * reconnects on any disconnect with exponential backoff + jitter,
    resuming from the last seen message (`since=<id>`) so nothing is missed;
  * tears down dead-quiet connections via a keepalive watchdog
    (`idle_timeout:`, default 90 s against the server's ~45 s keepalives);
  * treats non-2xx responses as fatal — a `403` won't fix itself, so the
    subscription delivers `{:down, %ExNtfy.Error{}}` and stops;
  * stops when its owner process dies.

### Style 1 — message passing

```elixir
{:ok, sub} = ExNtfy.subscribe("alerts", since: "10m")

receive do
  {:ntfy, ^sub, %ExNtfy.Message{} = message} -> handle(message)
  {:ntfy_lifecycle, ^sub, :connected} -> :ok
  {:ntfy_lifecycle, ^sub, :disconnected} -> :ok          # reconnect is automatic
  {:ntfy_lifecycle, ^sub, {:message_clear, message}} -> dismiss(message)
  {:ntfy_lifecycle, ^sub, {:message_delete, message}} -> remove(message)
  {:ntfy_lifecycle, ^sub, {:down, reason}} -> react(reason)
end

ExNtfy.unsubscribe(sub)
```

`open` and `keepalive` events are internal and never surface.

### Style 2 — a handler under supervision

Implement `ExNtfy.Handler` and put the subscription in your tree:

```elixir
defmodule MyApp.NtfyHandler do
  @behaviour ExNtfy.Handler

  @impl true
  def init(arg), do: {:ok, arg}

  @impl true
  def handle_message(%ExNtfy.Message{} = message, state) do
    MyApp.Alerts.process(message)
    {:ok, state}
  end

  @impl true  # optional callback
  def handle_lifecycle(:connected, state), do: {:ok, state}
  def handle_lifecycle(_event, state), do: {:ok, state}
end

children = [
  {ExNtfy.Subscription,
   topics: ["alerts", "backups"],
   handler: {MyApp.NtfyHandler, []},
   auth: {:token, "tk_..."},
   name: MyApp.NtfySub}
]
```

Callbacks run inside the subscription process; a crashing handler takes the
subscription down and your supervisor restarts both.

### Style 3 — a lazy stream

```elixir
ExNtfy.stream("alerts")
|> Stream.filter(&(&1.priority >= 4))
|> Enum.take(5)
```

Blocks the calling process; halting the enumeration (or the consumer dying)
stops the underlying subscription.

## Filters and reconnect tuning

All poll filters apply to subscriptions too, plus:

```elixir
ExNtfy.subscribe("alerts",
  since: :latest,            # start from the most recent cached message
  priority: [:high, :urgent],
  reconnect_base_ms: 1_000,  # backoff: base * 2^attempt, capped
  reconnect_max_ms: 60_000,
  idle_timeout: 90_000,
  reconnect: true            # false = stop instead of reconnecting
)
```

## Other transports

`format:` selects the wire format — semantics are identical everywhere:

  * `:json` (default) — ndjson over HTTP, the primary transport.
  * `:sse` — Server-Sent Events.
  * `:raw` — message bodies only; **no metadata**, so no `since` resume.
  * `:ws` — WebSocket, requiring the optional dependency:
    `{:mint_web_socket, "~> 1.0"}`. Without it, `subscribe/2` raises an
    `ArgumentError` telling you what to add.

## Telemetry

`[:ex_ntfy, :subscription, :connected | :disconnected | :message]` fire with
`%{topics: topics}` metadata; polls emit `[:ex_ntfy, :poll, ...]` spans.
