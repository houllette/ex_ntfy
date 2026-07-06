# Phase 5 Notes — Decisions & Surprises

## Reference §2.2 row-by-row param audit

All params encode via `ExNtfy.Subscribe.Options.to_query/1` (canonical names only, no
aliases) and are asserted in tests; `poll` is added by `ExNtfy.poll/2` itself.

| §2.2 param | Option | Notes |
|---|---|---|
| `poll` | — | Hard-coded `poll: "1"` by `Poller.poll/2`; not an option, so Phase 6 can reuse the same query builder without it |
| `since` | `:since` | Strings pass through **verbatim** (duration vs message-ID is server-disambiguated); non-negative unix int and `DateTime` → timestamp string; `:all`/`:latest` by name |
| `scheduled` | `:scheduled` | `true` → `1`; `false` emits nothing |
| `id` | `:id` | Verbatim exact-match filter |
| `message` | `:message` | Verbatim exact-match filter |
| `title` | `:title` | Verbatim exact-match filter |
| `priority` | `:priority` | Single value or list (OR semantics), `1..5` or the Phase-3 atoms; comma-joined ints. Empty list rejected |
| `tags` | `:tags` | List of strings/atoms, comma-joined (AND semantics) |
| `auth` | `:auth` + `:auth_via` | Client option since Phase 2; `auth_via: :query` tested merging with poll params |

## Decisions the plan left open

- **Malformed ndjson lines: skip-and-log** (the plan's recommendation). One bad line
  logs a `Logger.warning` and the rest of the poll succeeds. A non-binary 2xx body
  (server returned plain JSON, not ndjson) is still a hard
  `{:error, %Error{reason: {:invalid_response, body}}}`.
- **`open`/`keepalive` events are dropped** from poll results as planned; `message_clear`
  /`message_delete`/`poll_request` events are kept (sequenced clears/deletes are cached
  and meaningful to a poller). No `raw_events:` option, per the plan.
- **Topics normalize through comma-splitting**: `"a,b"`, `["a", "b"]`, and `["a,b"]` are
  equivalent — each topic is percent-escaped individually so commas survive as
  separators (topic names can't legally contain commas). Empty topics raise
  `ArgumentError`.
- **Priority validation is shared with Phase 3**: `Publish.Options.priority_int/1` was
  made public (`@doc false`) and `Subscribe.Options.validate_priority/1` reuses
  `Publish.Options.validate_priority/1` per element — one atom table for both sides.
- **`poll/2` got a telemetry span** (`[:ex_ntfy, :poll, :start | :stop | :exception]`,
  metadata `%{topics, base_url}`) mirroring the publish span. Not in the plan's test
  list, but tested; Phase 6 should follow the same pattern for subscriptions.
- **New `ExNtfy.Poller` module** rather than growing `Publisher`; Phase 6's streaming
  code should live in its own module too and reuse `Subscribe.Options.path/2` (already
  supports `:sse`/`:raw`/`:ws`) and `to_query/1` as-is.

## Surprises / things later phases should know

- **Req leaves `application/x-ndjson` bodies as binaries** (no decoder registered), so
  poll parsing is a plain `String.split("\n", trim: true)` + `Message.from_json/1` —
  the `trim: true` also handles trailing blank lines.
- **Elixir rejects nested captures** — `&URI.encode(&1, &URI.char_unreserved?/1)` is a
  compile error; the inner capture needs an explicit `fn`. (Publisher's version never
  hit this because it wasn't inside a capture.)
- Req keyword-merges per-request `:params` with the request's own, so `auth_via: :query`
  and poll params coexist — asserted exactly in a test.
- This is now the **third copy of the percent-escape-one-segment helper** (Publisher,
  Subscribe.Options). Still one line each; extract a shared helper only if a fourth
  appears or they start diverging.
- **cowlib CVEs still open** (EEF-CVE-2026-43966 MEDIUM / EEF-CVE-2026-43969 LOW,
  test-only via bypass → cowboy; 2.18.0 still newest as of 2026-07-05). Re-check
  `mix hex.audit` next phase.
- Coverage after this phase: 98.1% (gate is 90%); `poller.ex` and
  `subscribe/options.ex` are at 100%.
