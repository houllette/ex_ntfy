# ex_ntfy — Implementation Plan

A staged plan for building **ex_ntfy**, an Elixir SDK for [ntfy.sh](https://ntfy.sh) built on
[Req](https://hexdocs.pm/req). The SDK covers **every** documented option of ntfy's two core
capabilities: [publishing](https://docs.ntfy.sh/publish/) and
[subscribing](https://docs.ntfy.sh/subscribe/api/).

## How to use this plan (read this first, agent!)

Each `phase-NN-*/` subfolder is a **self-contained work package** designed to be executed by a
fresh agent context with no memory of previous sessions. To execute a phase:

1. Read this file top to bottom.
2. Read [`ntfy-api-reference.md`](./ntfy-api-reference.md) — a verified, exhaustive distillation
   of the ntfy HTTP API. It was checked against the upstream docs source
   (`github.com/binwiederhier/ntfy/docs`) in July 2026. Trust it over your training data; if
   something seems off, verify against https://docs.ntfy.sh before deviating.
3. Read your phase's `README.md` and verify the prerequisites listed there (each phase tells
   you which commands must pass before you start).
4. Work **test-first** (see TDD workflow below). Do not start work on a later phase.
5. When done, tick every box in your phase's *Definition of Done*, update `CHANGELOG.md`, and
   note anything surprising you learned in a `NOTES.md` inside your phase folder for future
   agents.

**Phases must be executed in order** (Phase 7 is optional and can be skipped or deferred; Phase 8
must come last).

| Phase | Folder | Delivers |
|-------|--------|----------|
| 1 | `phase-01-cleanup-and-scaffold/` | Remove OpenAPI-generator template cruft; real Mix project; deps; CI; quality tooling; test infrastructure |
| 2 | `phase-02-core-client-and-types/` | `ExNtfy.Client` (Req foundation), config, auth, error handling, `Message`/`Action`/`Attachment` structs + JSON parsing |
| 3 | `phase-03-publishing/` | `ExNtfy.publish/2,3` with **every** publish option (headers + JSON), webhook-GET publish, templates |
| 4 | `phase-04-attachments-and-lifecycle/` | File-upload attachments; sequence IDs: update / clear / delete notifications |
| 5 | `phase-05-polling/` | One-shot message fetching: `poll=1`, `since`, `scheduled`, all filters |
| 6 | `phase-06-streaming-subscriptions/` | Long-lived subscriptions (json/sse/raw streams), supervised `Subscription` process, reconnect/resume, handler behaviour |
| 7 | `phase-07-websocket/` *(optional)* | `/ws` transport via optional `mint_web_socket` dependency |
| 8 | `phase-08-docs-and-release/` | README, guides, ExDoc polish, opt-in live integration tests, Hex release readiness |

## Fixed design decisions

These were decided up front. Do **not** re-litigate them mid-phase; if one proves genuinely
wrong, record why in your phase's `NOTES.md` and make the smallest change that unblocks you.

- **Package name:** `ex_ntfy`; **top-level module:** `ExNtfy`.
- **HTTP client:** `Req` (`~> 0.5`). No Tesla, no Finch pools of our own, no OpenAPI generator.
- **Option validation:** `NimbleOptions` for all public-API keyword options. Invalid options
  raise `NimbleOptions.ValidationError` (fail fast, at call site).
- **Return convention:** `{:ok, result} | {:error, %ExNtfy.Error{}}` plus `!` bang variants
  that raise. Never raise on server/network errors in non-bang functions.
- **Publish transport:** JSON publish (`POST /`) is the default code path (cleanest mapping,
  no header-encoding pitfalls). Header-based publish is used where JSON can't go: binary
  attachment uploads and raw-body/template publishing. Header/query-only options
  (`cache`, `firebase`, `unified_push`, `template`) ride along as headers on the JSON request.
- **Streaming transport:** the `/json` stream endpoint is primary (upstream docs recommend it).
  SSE and raw parsing are also implemented (Phase 6); WebSocket is optional (Phase 7).
- **Config:** app-level defaults under `config :ex_ntfy` (`base_url`, `auth`, `receive_timeout`,
  ...), overridable per call via opts. Default `base_url` is `"https://ntfy.sh"`.
- **Telemetry:** emit `[:ex_ntfy, ...]` events (defined in Phases 3 and 6). Req's own telemetry
  remains available underneath.
- **Elixir/OTP floor:** Elixir `~> 1.15`, OTP 26 (CI matrix tests newest two Elixir versions).

## TDD workflow (applies to every phase)

1. For each behavior in your phase's *Test plan*, write a failing ExUnit test **before** the
   implementation. Commit-sized rhythm: red → green → refactor.
2. Unit/request tests use **`Req.Test`** (plug-based stubbing, `async: true`). Assert on the
   *outgoing request* (method, path, headers, query, body) — that is the SDK's contract.
3. Streaming tests (Phases 5–7) use **Bypass** for a real socket with chunked responses.
4. Pure functions (option encoding, header building, message parsing) get plain unit tests and
   doctests — prefer pushing logic into pure functions so most tests need no HTTP at all.
5. Every public function gets `@doc`, `@spec`, and a doctest where the example is meaningful.
6. Quality gates — all must pass before a phase is "done":

   ```sh
   mix format --check-formatted
   mix credo --strict
   mix dialyzer
   mix coveralls   # ≥ 90% line coverage
   ```

## Repository conventions

- `lib/ex_ntfy.ex` — public facade (delegates); `lib/ex_ntfy/` — implementation modules.
- `test/` mirrors `lib/` one-to-one (`test/ex_ntfy/publisher_test.exs` ↔
  `lib/ex_ntfy/publisher.ex`); shared helpers in `test/support/`.
- Follow the Elixir library guidelines (https://hexdocs.pm/elixir/library-guidelines.html):
  no forced supervision tree on users, no global state beyond app config, no `Application`
  callback unless a phase explicitly needs one (Phase 6 discusses this).
- Keep `CHANGELOG.md` in Keep-a-Changelog format; every phase appends to `[Unreleased]`.
