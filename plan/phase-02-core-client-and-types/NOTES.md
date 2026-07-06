# Phase 2 Notes — Decisions & Surprises

## Decisions the plan left open

- **Action struct: one struct, not four.** `ExNtfy.Action` holds `type` plus the union of
  all fields (`label`, `url`, `method`, `headers`, `body`, `intent`, `extras`, `value`,
  `clear`); fields not applicable to a type are `nil`. Rationale: parsing stays a single
  lenient pass, pattern-matching on `type` is just as ergonomic as four structs, and
  Phase 3's outgoing encoding can dispatch on the same `type` field. Also added an `id`
  field — the server includes one on actions in received messages.
- **Unknown `event` (and unknown action type) → `{:unknown, string}`.** Chosen over keeping
  the bare string so `event` is always pattern-matchable by atom for known events, and
  unknown values are explicit rather than silently string-typed.
- **`request/2` exists; callers don't use Req directly.** `Client.request(req_or_opts,
  req_opts)` runs the request and normalizes: 2xx → `{:ok, Req.Response.t()}`, other
  statuses → `{:error, %ExNtfy.Error{}}` via `Error.from_response/2`, transport failures →
  `{:error, %ExNtfy.Error{reason: e}}`. Feature phases build request options and call it.
- **`Config.resolve/2` takes `app_env` as an argument** (default
  `Application.get_all_env(:ex_ntfy)`) so precedence tests stay pure and `async: true`.
  Unknown keys in the app env are ignored (env may hold unrelated entries); unknown keys in
  per-call opts raise `NimbleOptions.ValidationError`.
- **`from_map/1` returns `{:ok, t} | {:error, ...}`** (same tuple shape as `from_json/1`),
  erroring only when an always-present field (`id`, `time`, `event`, `topic`) is missing.

## Surprises / things later phases should know

- **`Req.merge/2` merges headers by name** (same-name replaces, different-name adds), so
  `req_options: [headers: ...]` overrides the default user-agent without dropping it when
  adding unrelated headers. Verified by tests; `req_options` is merged last so `plug:`
  injection works.
- **`ExNtfy.TestHelpers.req_stub/1` changed shape** (from Phase 1): it now returns
  `[req_options: [plug: {Req.Test, ExNtfy}]]` so its result can be passed directly as
  client options — `Client.new(req_stub(fun))` — since `plug:` must travel through
  `req_options` to survive `Config` validation.
- **App-env client tests are `async: false`** (`client_app_config_test.exs`); ExUnit runs
  sync modules after all async ones, so mutating `:ex_ntfy` env there can't race the async
  suites.
- **Coverage gate added:** `coveralls.json` sets `minimum_coverage: 90` (and skips
  `test/support`). Currently at 98.3%.
- **Transport-error tests need `retry: false`** — Req's default retry treats `:timeout` as
  transient and would sleep through 3 retries. This also exercises the `retry` pass-through.
- **cowlib CVEs still open** (EEF-CVE-2026-43966 MEDIUM / EEF-CVE-2026-43969 LOW,
  test-only via bypass → cowboy). 2.18.0 remains the newest release as of 2026-07-05;
  re-check `mix hex.audit` next phase.
- The query-auth encoding was verified against the reference's example credentials:
  `{:basic, "testuser", "fakepassword"}` → `?auth=QmFzaWMgZEdWemRIVnpaWEk2Wm1GclpYQmhjM04zYjNKaw`.
