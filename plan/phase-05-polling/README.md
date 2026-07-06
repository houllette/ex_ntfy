# Phase 5 — Polling (one-shot message fetching)

## Mission

Implement one-shot retrieval of cached messages — the `poll=1` mode of the subscribe API,
with the full `since` / `scheduled` / filter surface (reference §2.1–§2.2). This phase also
builds the **subscribe option schema and URL builder that Phase 6 reuses**, so factor
accordingly (`ExNtfy.Subscribe.Options`).

## Prerequisites

Phases 1–4 complete. Read reference §2 fully. Note: polling uses a plain request/response
(the connection closes after cached messages are sent), so Req.Test still works — no
streaming machinery needed yet.

## Public API

```elixir
ExNtfy.poll(topics, opts \\ [])   # {:ok, [%ExNtfy.Message{}]} | {:error, %ExNtfy.Error{}}
ExNtfy.poll!(topics, opts \\ [])
```

- `topics`: String or list of Strings (joined with commas in the path).
- Endpoint: `GET /<topics>/json?poll=1` — ndjson body; split lines, parse each with
  `Message.from_map/1`, drop `open`/`keepalive` events from the returned list (document
  this; expose `raw_events: true` opt to keep everything? No — keep the API small; document
  that poll responses contain only cached `message` events anyway).

### Options → `ExNtfy.Subscribe.Options` (shared with Phase 6)

| Option | Type | Encodes to |
|---|---|---|
| `:since` | String duration (`"10m"`) \| integer unix \| `DateTime` \| message id String \| `:all` \| `:latest` | `since=` |
| `:scheduled` | boolean | `scheduled=1` |
| `:id` | String | `id=` |
| `:message` | String | `message=` |
| `:title` | String | `title=` |
| `:priority` | single or list of 1..5/atoms (same atoms as Phase 3) | comma-joined `priority=` |
| `:tags` | list of String/atom | comma-joined `tags=` |
| plus all `ExNtfy.Client` options | | |

Design notes:

- `since: <string>` is ambiguous between duration and message-id — pass strings through
  verbatim (the server disambiguates); only atoms/ints/DateTime get transformed. Document it.
- Priority filter accepts a *list* (OR semantics) unlike publish — hence a separate schema
  from Phase 3, but share the atom→int mapping helper.
- The URL builder must produce: path from topic list, query from options. Pure function,
  heavily doctested — Phase 6 calls it with `poll` absent.
- `poll=1` is added by `poll/2` itself, not an option.

## Test plan (TDD — write these first)

1. URL/query builder unit tests: every option row above, single + multi-topic paths,
   topic path-escaping, `DateTime` since → unix, `:latest`/`:all`, priority list
   `[:high, 5]` → `"4,5"`, tags join.
2. `poll/2` request shape: `GET /a,b/json?poll=1&...` (Req.Test).
3. Response parsing: ndjson with several `message` events → ordered `[%Message{}]`;
   empty body → `{:ok, []}`; a trailing blank line doesn't crash; malformed line →
   decide + test (skip with a `Logger.warning`, or error the whole call — record choice
   in NOTES.md; recommendation: skip-and-log, servers shouldn't fail a whole poll for
   one bad line).
4. Filters passthrough: `id`, `message`, `title` land verbatim in query.
5. Auth: token auth header present on poll; `auth_via: :query` works here too.
6. Error paths: 404/403 → `%ExNtfy.Error{}`.

## Definition of Done

- [ ] All test-plan items green, written test-first
- [ ] `Subscribe.Options` module documented as shared infrastructure (Phase 6 pointer in
      its moduledoc)
- [ ] Every param row in reference §2.2 reachable and tested — row-by-row audit in NOTES.md
- [ ] Quality gates pass; CHANGELOG updated; NOTES.md written

## Out of scope

Long-lived streaming connections, reconnect logic, keepalive handling — all Phase 6.
