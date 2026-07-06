# Phase 3 — Publishing (full option coverage)

## Mission

Implement `ExNtfy.publish/2,3` and friends covering **every** publish option in
`plan/ntfy-api-reference.md` §1 — except binary attachment uploads and the
update/clear/delete lifecycle, which are Phase 4. This is the largest phase; the reference
doc's §1.2/§1.3 tables are the acceptance checklist.

## Prerequisites

Phases 1–2 complete: `ExNtfy.Client`, `ExNtfy.Error`, `ExNtfy.Message` exist and their tests
pass. Read reference §1 fully.

## Public API

```elixir
# JSON publish (default path): POST / with JSON body
ExNtfy.publish(topic, message, opts \\ [])            # {:ok, %ExNtfy.Message{}} | {:error, %ExNtfy.Error{}}
ExNtfy.publish!(topic, message, opts \\ [])

# Raw-body publish for templating/webhook payloads: PUT/POST /<topic>, body untouched,
# options as headers/query (reference §1.6)
ExNtfy.publish_raw(topic, body, opts \\ [])

# Webhook-style GET (everything in the query string), for parity with the API
ExNtfy.trigger(topic, opts \\ [])
```

Facade delegates to `ExNtfy.Publisher`. `message` may be `nil` for option-only publishes.

### Options (one NimbleOptions schema — the heart of this phase)

| Option | Type accepted | Encodes to |
|---|---|---|
| `:title` | String | `title` |
| `:priority` | 1..5 \| `:min` `:low` `:default` `:high` `:max` `:urgent` | int |
| `:tags` | list of String/atom | array / comma-joined |
| `:markdown` | boolean | `markdown` |
| `:delay` | String \| non-neg integer (unix) \| `DateTime` | string |
| `:click` | String URL | `click` |
| `:icon` | String URL | `icon` |
| `:attach` | String URL | `attach` |
| `:filename` | String | `filename` |
| `:actions` | list of `ExNtfy.Action` or maps (≤ 3) | JSON array / short format |
| `:email` | String \| `true` (→ `"yes"`) | `email` |
| `:call` | String \| `true` (→ `"yes"`) | `call` |
| `:sequence_id` | String | `sequence_id` |
| `:cache` | boolean (false → header `Cache: no`) | header only |
| `:firebase` | boolean (false → header `Firebase: no`) | header only |
| `:unified_push` | boolean | header only |
| `:template` | `true` \| `:github` \| `:grafana` \| `:alertmanager` \| String | header/query only |
| `:poll_id` | String (pass-through, `@doc false`-level prominence) | header only |
| plus all `ExNtfy.Client` options (`:base_url`, `:auth`, ...) | | |

### Encoding rules (implement as pure functions in `ExNtfy.Publish.Options`)

- **JSON path** (`publish/3`): body gets the §1.3 JSON fields; `cache`/`firebase`/
  `unified_push`/`template`/`poll_id` become headers on the same request.
- **Header path** (`publish_raw/3`, `trigger/2`): every option becomes its canonical
  header (§1.2) or query param (for `trigger`). Non-ASCII header values are RFC 2047
  B-encoded (`=?UTF-8?B?...?=`) — implement `rfc2047_encode/1`, ASCII passes through
  untouched. Actions encode to **short format** here unless the caller supplied raw JSON;
  quote values containing `,`/`;`.
- `DateTime` delay → unix timestamp string. Integer → string. String passes through.
- Reject unknown options loudly (NimbleOptions default) — a typo must not silently drop a
  feature.

### Telemetry

Wrap requests in `:telemetry.span/3`: `[:ex_ntfy, :publish, :start | :stop | :exception]`
with metadata `%{topic, base_url}` (never include auth or message contents).

## Test plan (TDD — write these first)

Request-shape tests via Req.Test (assert on `conn`: method, path, decoded body, headers):

1. Minimal publish: `POST /` with `{"topic": t, "message": m}`; response parses to
   `%ExNtfy.Message{}` (id/time/event fields set).
2. **Kitchen-sink publish**: every JSON option at once — assert the exact JSON body map, and
   that `cache: false`, `firebase: false`, `template: :github` landed as headers not JSON.
3. Priority: each atom maps to its int; `6` / `:bogus` raise `NimbleOptions.ValidationError`.
4. Tags: atoms and strings mix; preserved order.
5. Delay: `DateTime`, integer, `"30m"`, `"tomorrow, 3pm"` all encode; negative int rejected.
6. Actions: all four types (view/broadcast/http/copy) with all sub-fields JSON-encode
   correctly; > 3 actions rejected; short-format encoding unit-tested per type including
   quoting of `,`/`;` and `extras.`/`headers.` flattening.
7. `email: true` → `"yes"`; same for `call`.
8. `publish_raw/3`: body passes through byte-identical; UTF-8 title emitted RFC 2047-encoded
   (assert exact encoded string); `template: true` → `Template: yes` header; JSON webhook
   body + inline template scenario end-to-end shape.
9. `trigger/2`: `GET /<topic>/trigger`, options only in query string, no body.
10. Error paths: 429 with ntfy JSON error → `{:error, %ExNtfy.Error{code: 42901, http: 429}}`;
    transport error (`Req.Test.transport_error/2`) → `{:error, %ExNtfy.Error{reason: ...}}`;
    `publish!/3` raises `ExNtfy.Error`.
11. Telemetry: `:start`/`:stop` emitted with topic metadata (attach a test handler).

Doctests: options encoding examples in `ExNtfy.Publish.Options`.

## Definition of Done

- [ ] Every header row in reference §1.2 (except `X-Poll-ID` prominence) reachable via a
      documented option — do a literal row-by-row audit and record it in NOTES.md
- [ ] All test-plan items green, written test-first
- [ ] `ExNtfy` moduledoc gains a Publishing section with copy-pasteable examples
- [ ] Quality gates pass; CHANGELOG updated; NOTES.md written

## Out of scope

Binary uploads, update/clear/delete (Phase 4); polling/subscribing (Phases 5–6).
