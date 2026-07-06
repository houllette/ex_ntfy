# Phase 6 — Streaming Subscriptions

## Mission

Long-lived subscriptions over ntfy's HTTP streams: a supervised `ExNtfy.Subscription`
GenServer consuming `/json` (primary), with `/sse` and `/raw` parsers for completeness,
automatic reconnect with `since=<last id>` resume, keepalive watchdog, and two consumption
styles (message-passing and a handler behaviour). This is the hardest phase — most of the
work is process design, not HTTP.

## Prerequisites

Phases 1–5 complete; `ExNtfy.Subscribe.Options` URL builder exists (Phase 5). Read reference
§2 fully, especially §2.3. Bypass (already a dep) is the test server — Req.Test can't
exercise real chunked-transfer timing.

## Public API

```elixir
# Message-passing style: events delivered to owner (default self()) as
#   {:ntfy, subscription_pid, %ExNtfy.Message{}}          for :message events
#   {:ntfy_lifecycle, subscription_pid, event}            for :connected/:disconnected/{:down, reason}
{:ok, pid} = ExNtfy.subscribe(topics, opts)
:ok = ExNtfy.unsubscribe(pid)

# Handler style: user module implementing ExNtfy.Handler
{:ok, pid} = ExNtfy.subscribe(topics, handler: {MyHandler, init_arg}, ...)

# Child-spec friendly:
ExNtfy.Subscription.start_link(topics: ..., handler: ..., name: ...)  # for user supervision trees

# Lazy Enumerable (bonus, small): blocks the calling process
ExNtfy.stream(topics, opts) :: Enumerable.t(ExNtfy.Message.t())
```

### `ExNtfy.Handler` behaviour

```elixir
@callback init(arg) :: {:ok, state}
@callback handle_message(%ExNtfy.Message{}, state) :: {:ok, state}
@callback handle_lifecycle(:connected | :disconnected | {:message_clear | :message_delete, %ExNtfy.Message{}}, state) :: {:ok, state}  # optional callback
```

`message_clear`/`message_delete` events route to `handle_lifecycle` (or a dedicated optional
callback — decide, document, test); `open`/`keepalive` are internal and never surface.

### Subscription process design

- `ExNtfy.Subscription` is a GenServer owning the HTTP connection. Run the Req request with
  `into: :self` (`Req.parse_message/2`) so chunks arrive as messages in the GenServer inbox —
  no extra task process needed. (If `into: :self` proves awkward across reconnects, a linked
  Task + `into: fn` sending to the parent is the fallback; record the choice in NOTES.md.)
- **Line reassembly:** chunks are not line-aligned. Buffer partial trailing lines; emit only
  on `\n`. Property-style test: any chunking of a fixture stream yields identical events.
- **Format parsers** (pure modules, `ExNtfy.Stream.{NDJSON, SSE, Raw}`): ndjson (one JSON/line);
  SSE (`event:`/`data:` fields, blank-line dispatch — only `data:` carries the JSON we parse);
  raw (line = message body only → synthesize minimal `%Message{event: :message, message: line}`;
  empty line = keepalive). `format: :json | :sse | :raw` option, default `:json`. Document
  that `:raw` loses all metadata (no ids → no resume).
- **Resume & reconnect:** track last seen `message` event id; on any disconnect, reconnect
  after backoff with `since=<last_id>` (or the user's original `since` if nothing seen yet).
  Exponential backoff with jitter, e.g. 1s → 2s → 4s → ... capped 60s; reset on successful
  `open`. Opt: `reconnect: false` to die instead (`:stop` with reason).
- **Keepalive watchdog:** server keepalives arrive ~45 s apart on quiet topics. `:timeout`
  timer (default 90_000 ms, opt `idle_timeout:`) reset on *any* stream activity; on expiry,
  tear down the connection and go through reconnect flow.
- Owner monitoring: subscription terminates when its owner dies (message-passing mode).
- Options: everything from `Subscribe.Options` (filters, since, scheduled) + `Client`
  options; **no `poll`** (rejected here).
- Telemetry: `[:ex_ntfy, :subscription, :connected | :disconnected | :message]` with
  `%{topics: ...}` metadata.
- No forced app-level supervision: users either get a linked pid from `subscribe/2` or put
  `ExNtfy.Subscription` in their own tree. Do NOT add an `Application` callback.

## Test plan (TDD — write these first)

Pure parser tests (majority of the suite — no processes):

1. NDJSON/SSE/Raw parsers against fixture streams; partial-line buffering across arbitrary
   chunk splits (drive with a list of random split points, fixed seed).
2. SSE: multi-field events, comment lines (`:`), CRLF endings.
3. Raw: empty-line keepalive skipped, body lines → synthesized messages.

Process tests against Bypass (chunked responses, `async: false` where needed):

4. `subscribe/2` connects to `GET /<topics>/json` with filter/since query from options;
   `open` consumed internally; `message` events delivered as `{:ntfy, pid, %Message{}}`.
5. Keepalive events never delivered; but they reset the idle watchdog (send keepalives with
   short `idle_timeout` and assert no reconnect).
6. Idle timeout with *no* traffic triggers reconnect (Bypass sees a second request) with
   `since=<last id>` when a message had been seen.
7. Server closes connection → reconnect with backoff (assert second request; keep backoff
   base configurable so tests run fast).
8. `message_clear`/`message_delete` routed to lifecycle handling with parsed `%Message{}`.
9. Handler mode: callbacks invoked in order with threaded state; handler crash policy
   (terminate subscription — assert).
10. `unsubscribe/1` stops cleanly; owner death stops the subscription.
11. `ExNtfy.stream/2` yields messages lazily and halts cleanly when the consumer halts
    (`Stream.take(1)`).
12. Auth: header auth on stream request; `auth_via: :query` produces `?auth=` (this is the
    mode WebSocket/SSE-limited clients need — verify encoding end-to-end here).

## Definition of Done

- [ ] All test-plan items green, written test-first; parsers ≥ 95% covered
- [ ] Moduledocs: consumption-style guide (message-passing vs handler vs stream) with
      supervision examples
- [ ] Quality gates pass; CHANGELOG updated; NOTES.md records process-design decisions
      (into: :self vs task, handler-crash policy)

## Out of scope

WebSocket transport (Phase 7). Persistent client-side message stores or delivery guarantees
beyond reconnect-resume.
