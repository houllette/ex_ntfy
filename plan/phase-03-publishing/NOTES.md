# Phase 3 Notes — Decisions & Surprises

## Reference §1.2 row-by-row header audit

Every header row is reachable via a documented option; all encode on all three
paths (JSON body/header, raw-body header, trigger query) unless noted.

| §1.2 header | Option | Notes |
|---|---|---|
| `X-Message` | `:message` | Also the positional arg to `publish/3` (positional wins). As an option it serves `trigger/2` and inline templates on `publish_raw/3` |
| `X-Title` | `:title` | RFC 2047-encoded on the header path when non-ASCII |
| `X-Priority` | `:priority` | `1..5` or `:min`/`:low`/`:default`/`:high`/`:max`/`:urgent` |
| `X-Tags` | `:tags` | Atoms/strings mix; JSON array on the JSON path, comma-joined elsewhere |
| `X-Delay` (`X-At`, `X-In`) | `:delay` | `DateTime` → unix string, non-neg integer → string, string pass-through. Canonical header only; aliases not needed |
| `X-Actions` | `:actions` | Structs/maps → JSON array (JSON path) or short format (header/query paths); a raw JSON string passes through untouched |
| `X-Click` | `:click` | |
| `X-Attach` | `:attach` | URL attachments only; binary uploads are Phase 4 |
| `X-Markdown` | `:markdown` | JSON boolean on the JSON path; `yes`/omitted on header/query paths |
| `X-Icon` | `:icon` | |
| `X-Filename` | `:filename` | |
| `X-Email` | `:email` | `true` → `"yes"` |
| `X-Call` | `:call` | `true` → `"yes"` |
| `X-Sequence-ID` | `:sequence_id` | Header/JSON field only this phase; path-based `POST /<topic>/<seq>` is Phase 4 |
| `X-Cache` | `:cache` | `false` → `no`; `true` (server default) emits nothing. Header-only, even on JSON publishes |
| `X-Firebase` | `:firebase` | Same shape as `:cache` |
| `X-UnifiedPush` | `:unified_push` | `true` → `1`; header-only |
| `X-Poll-ID` | `:poll_id` | Pass-through, documented as internal; header-only |
| `X-Template` | `:template` | `true` → `yes`, `:github`/`:grafana`/`:alertmanager`, or a custom name string; header-only |
| `Content-Type` | — (deliberate) | `text/markdown` is redundant with `:markdown`; anything else is reachable via the `req_options: [headers: ...]` escape hatch |
| `Authorization` | `:auth` | Client option since Phase 2 (`:auth_via` covers the `?auth=` query form) |

## Decisions the plan left open

- **`:message` is a schema option**, not just a positional argument. `trigger/2` has no
  message positional, and inline templating needs `X-Message` to carry a Go template while
  the body carries the webhook JSON — so the option is required for §1.2 coverage. On
  `publish/3` the positional argument wins via `Keyword.put`.
- **Option splitting:** `Publisher` splits the mixed keyword list with
  `Keyword.split(opts, ExNtfy.Config.keys())` (new public `Config.keys/0`). Client keys go
  to `Client.new/1`; everything else — including typos — hits the publish schema, so
  unknown options raise `NimbleOptions.ValidationError` before any request.
- **Short format emits fully-named `key=value` pairs** (`action=view, label=..., url=...`),
  not the positional form — unambiguous and both are accepted by the server. `headers`/
  `extras` maps flatten to `headers.<name>=`/`extras.<key>=` with **sorted keys** for
  deterministic output. Quoting: double quotes when a value contains `,`/`;`/`'`, single
  quotes when it contains `"`; a value containing both quote kinds is unsupported (ntfy has
  no escaping). `id` is never emitted in short format (server-assigned); `clear` only when
  `true`.
- **`Action.to_json_map/1` round-trips `from_map/1` exactly** on all four fixture actions
  (including `id`); `nil` fields and a `false` `clear` are omitted. Plain ntfy-shaped maps
  pass through untouched on the JSON path and go through `from_map/1` for short format.
- **Query names use the documented short aliases** where the canonical name isn't a valid
  bare word: `sid` (sequence ID), `up` (UnifiedPush), `poll-id`. Names are atoms so Req
  keyword-merges per-request `:params` with the `?auth=` param from `auth_via: :query`.
- **`publish_raw/3` uses POST** (PUT is equivalent server-side; PUT + binary upload
  semantics arrive in Phase 4).
- **A 2xx response whose body isn't a parsable message** becomes
  `{:error, %Error{reason: {:invalid_response, details}}}` — `Error.reason` widened from
  `Exception.t() | nil` and `message/1` gained an `inspect/1` clause for non-exception
  reasons.

## Surprises / things later phases should know

- **telemetry 1.4.2 was already in `mix.lock`** (transitive via Finch); it's now a direct
  dependency (`~> 1.4`). `:telemetry.span/3` measurements come for free
  (`system_time`/`duration`/`monotonic_time`).
- **RFC 2047 is applied to every header value on the header path** (ntfy's Go
  `mime.WordDecoder` decodes any parameter header), as a single encoded word — no 75-char
  folding. ASCII passes through untouched, so this is a no-op for typical values.
- The Options moduledoc interpolates `NimbleOptions.docs/1` from a plain module-body
  variable (`schema_def`) so the schema documents itself; keep the two in one place.
- Phase 4's update/clear/delete can reuse `Publisher.topic_path/1` (URI-encodes the topic
  segment) and the same `span/3` telemetry wrapper — consider a shared helper if a third
  copy appears.
- **cowlib CVEs still open** (EEF-CVE-2026-43966 MEDIUM / EEF-CVE-2026-43969 LOW,
  test-only via bypass → cowboy; 2.18.0 still newest as of 2026-07-05). Re-check
  `mix hex.audit` next phase.
- Coverage after this phase: 97.4% (gate is 90%).
