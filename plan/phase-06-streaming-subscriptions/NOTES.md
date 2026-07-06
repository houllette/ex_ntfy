# Phase 6 Notes — Decisions & Surprises

## Process-design decisions (the ones the plan asked to record)

- **`into: :self` won, no task process.** The Subscription GenServer runs
  `Client.request(req, into: :self, retry: false)` in `handle_continue`/`:reconnect`;
  chunks arrive as ordinary `handle_info` messages parsed with `Req.parse_message/2`, and
  `Req.cancel_async_response/1` tears connections down in `terminate/2` and on idle
  timeout. It survived reconnects fine — the fallback (linked Task + `into: fn`) was never
  needed. Stale messages from a canceled response return `:unknown` from `parse_message`
  and are dropped. Note: the connect call blocks the GenServer until status+headers arrive,
  so calls to the process during a connect wait; acceptable for a connection-owning process.
- **Req's retry is force-disabled on the stream request** (`retry: false` per-request,
  overriding any user `retry:` client option) — the subscription's own backoff loop is in
  charge of retries.
- **Handler-crash policy: terminate.** Handler callbacks run unrescued inside the
  subscription process; a raise crashes the GenServer (asserted in tests). Supervision is
  the recovery story — `ExNtfy.Subscription` docs show the child-spec usage.
- **Non-2xx connect responses are fatal** even with `reconnect: true` — a 403/404 won't fix
  itself by retrying; the subscription delivers `{:down, %Error{http: status}}` and stops
  `{:shutdown, error}`. Only transport-level failures and disconnects reconnect. The error
  carries the status only (the async body is not drained for the error JSON).
- **Backoff reset**: on the server's `open` event for `:json`/`:sse`; `:raw` has no `open`
  event, so it resets on successful connect instead. Backoff is
  `base * 2^(attempt-1)` capped at `reconnect_max_ms`, plus 0–25% jitter;
  `reconnect_base_ms`/`reconnect_max_ms` are options so tests run at 20/100 ms.
- **Owner monitoring, not just links**: the owner is monitored and the subscription stops
  `:normal` on its `DOWN` — a link alone wouldn't stop it when the owner exits `:normal`.
  Owner defaults to the caller only in message-passing mode (no `handler:`).
- **`stream/2` starts the subscription unlinked** (`GenServer.start`) and relies on owner
  monitoring for consumer-crash cleanup; the consumer monitors the subscription so it halts
  rather than hangs if the subscription dies. `Enum.take/2` halting stops it via the
  `Stream.resource/3` after-fun.
- **`message_clear`/`message_delete` route as lifecycle events**
  (`{:ntfy_lifecycle, pid, {event, message}}` / `handle_lifecycle({event, message}, state)`)
  rather than a dedicated callback — they're state changes about prior messages, not new
  content. `poll_request` and unknown events are ignored.
- **Parsers return every event** (including `open`/`keepalive`); filtering is the
  Subscription's job — it needs `open` for backoff reset and any-activity for the watchdog.

## Surprises / things later phases should know

- **Bypass + streaming teardown was the phase's one real fight.** When the SDK closes a
  connection client-side (cancel, idle timeout, stop), cowboy exit-signals the still-blocked
  Bypass handler with `:shutdown`; Bypass records that as a failed expectation and re-raises
  it in `on_exit` — tests fail `** (exit) shutdown` *after their bodies pass*, with no
  useful trace. Fix: the test handler traps exits and returns the conn on `{:EXIT, _, _}`
  (see `expect_stream/2` in `subscription_test.exs`). Phase 7's WebSocket tests will need
  the same trick if they use Bypass.
- `Finch.async_request/3` spawn-links its request process to the caller — harmless here
  (it exits `:normal`; cancel unlinks before killing), but worth knowing when reasoning
  about the subscription's link set.
- Doc heredocs interpolate: moduledoc examples with `#{...}` need `\#{...}` escaping.
- Elixir 1.20 warns on `binary-size(size)` without a pin when `size` is bound outside the
  match — `binary-size(^size)`.
- `%Message{}` literals with explicit `id: nil, time: nil, topic: nil` satisfy
  `@enforce_keys` (enforcement is about presence in the literal, not non-nil) — how
  `Stream.Raw` synthesizes metadata-less messages.
- `Error.from_response/2` gained an `is_struct` clause: with `into: :self` a non-2xx
  response body is an unconsumed `%Req.Response.Async{}`, which the map clause would have
  crashed on (`Access` on a struct).
- **cowlib CVEs still open** (EEF-CVE-2026-43966 MEDIUM / EEF-CVE-2026-43969 LOW,
  test-only via bypass → cowboy; 2.18.0 still newest as of 2026-07-05). Re-check
  `mix hex.audit` next phase.
- Coverage after this phase: 96.7% (parsers 100%, subscription 92.9% — the misses are
  defensive branches: transport error mid-stream, trailers, stale idle refs).
