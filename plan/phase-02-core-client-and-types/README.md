# Phase 2 — Core Client & Types

## Mission

Build the shared foundation every feature phase sits on: a Req-based client with
configuration and authentication, the ntfy error type, and the structs + parsing for ntfy's
message schema. After this phase, adding a feature means "build request options, call
`Client.request/2`, parse with `Message.from_map/1`".

## Prerequisites

Phase 1 complete: `mix test`, `mix credo --strict`, `mix dialyzer` green on the skeleton;
`req` and `nimble_options` in deps. Read `plan/ntfy-api-reference.md` §2.4, §3, §1.8.

## Deliverables

### `ExNtfy.Client` (`lib/ex_ntfy/client.ex`)

Thin wrapper producing a configured `Req.Request`:

```elixir
@type option ::
        {:base_url, String.t()}          # default "https://ntfy.sh"
        | {:auth, auth()}                # see below
        | {:auth_via, :header | :query}  # default :header; :query builds ?auth=<token> (§3)
        | {:receive_timeout, timeout()}
        | {:retry, ...}                  # pass-through to Req retry options
        | {:req_options, keyword()}      # escape hatch, merged last
@type auth :: {:basic, user :: String.t(), pass :: String.t()} | {:token, String.t()} | nil

new(opts \\ []) :: Req.Request.t()
request(req_or_opts, method_path_etc) # or have callers use Req directly on new/1's result — pick one and document it
```

- Per-call opts override app config (`Application.get_env(:ex_ntfy, ...)`), which overrides
  defaults. Implement precedence in one pure function: `Config.resolve(opts)` — easy to test.
- `auth_via: :query` encodes the **full** `Authorization` value as unpadded base64url into
  `?auth=` (needed later for WebSocket/EventSource-style clients; verify against reference §3).
- Accept `plug:` through `req_options` so tests can inject `plug: {Req.Test, ExNtfy}`.
- Set a `user-agent` like `ex_ntfy/<version> (Elixir)`.

### `ExNtfy.Error` (`lib/ex_ntfy/error.ex`)

`defexception` with fields `code` (ntfy numeric code), `http` (status), `error` (server
message), `link`, `reason` (for transport errors: `%Req.TransportError{}` etc.). Constructors:
`from_response(status, body)` (parses ntfy's JSON error shape, tolerates non-JSON bodies) and
`from_exception(e)`. Implements `message/1` for readable raising.

### Message schema structs (`lib/ex_ntfy/message.ex`, `action.ex`, `attachment.ex`)

- `ExNtfy.Message` — all fields from reference §2.4, plus `raw :: map()` retaining the
  original decoded map (lenient forward-compat). `event` as atom
  (`:open | :keepalive | :message | :message_clear | :message_delete | :poll_request`,
  unknown → `{:unknown, string}` or keep string — pick one, document, test it).
  `from_map/1` and `from_json/1` (returns `{:ok, t} | {:error, term}`).
- `ExNtfy.Attachment` — `name`, `url`, `type`, `size`, `expires`.
- `ExNtfy.Action` — one struct with `type :: :view | :broadcast | :http | :copy` plus the
  union of fields (`label`, `url`, `method`, `headers`, `body`, `intent`, `extras`, `value`,
  `clear`), or four structs — **decide, document in NOTES.md**. Must round-trip: parse from
  incoming JSON here; Phase 3 adds outgoing encoding to the same module.

All structs: `@type t`, `@enforce_keys` where the API guarantees presence (`id`, `time`,
`event`, `topic` on Message; `name`, `url` on Attachment).

## Test plan (TDD — write these first)

Pure parsing tests (no HTTP):

1. `Message.from_map/1` on a full-featured message fixture (every field incl. actions,
   attachment, sequence_id, icon, content_type) and on a minimal `keepalive`/`open` event.
2. Unknown `event` value and unknown extra fields don't crash; `raw` preserves them.
3. `Action` parsing for all four types incl. `extras`/`headers` maps and `clear`.
4. Priority stays integer 1–5; missing optional fields are `nil` (not `""`).
5. `Error.from_response/2` on ntfy JSON error (`{"code":42901,"http":429,...}`), on
   plain-text body, on empty body.

Fixtures: create `test/support/fixtures.ex` with real ntfy payloads copied from the reference
doc examples.

Client tests (Req.Test, `async: true`):

6. Default base_url is `https://ntfy.sh`; `base_url` opt and app config override in the right
   precedence order.
7. `{:basic, u, p}` sets `Authorization: Basic ...`; `{:token, t}` sets `Bearer ...`;
   `auth_via: :query` sets no header but `?auth=` with correct unpadded-base64url value
   (assert the exact expected string for a known input).
8. `req_options` merge wins over computed defaults; user-agent header present.

## Definition of Done

- [ ] All test-plan items implemented test-first and green
- [ ] `@spec`/`@doc` on all public functions; doctests for `from_map/1` and `Config.resolve/1`
- [ ] Quality gates pass (format, credo --strict, dialyzer, coveralls ≥ 90%)
- [ ] CHANGELOG updated; `NOTES.md` records the Action-struct decision and anything surprising

## Out of scope

Publishing or subscribing functions (Phases 3–6); telemetry events (Phase 3); retries beyond
Req defaults (revisit only if a later phase demands it).
