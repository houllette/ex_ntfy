# Contributing to ExNtfy

Thanks for helping out! This project is small and disciplined — the rules
below keep it that way.

## Development setup

```sh
mix deps.get
mix test
```

Elixir ~> 1.20 with the built-in `JSON` module is required (CI runs OTP 28
and 29). No external services are needed for the default suite.

## The workflow: tests first

This library was built test-first, phase by phase (the `plan/` folder holds
the phase specs and per-phase `NOTES.md` decision records — read them for
history and rationale). Contributions should follow the same shape:

1. **Write the failing test first.** HTTP request/response behavior is tested
   with `Req.Test` stubs (see `ExNtfy.TestHelpers.req_stub/1`); streaming
   behavior against real servers in-test — Bypass for chunked HTTP,
   Bandit + WebSock for WebSocket (`test/support/ws_test_server.ex`).
2. Implement until green.
3. If you discovered a bug, the regression test lands in the same commit as
   the fix.

Encoding behavior is asserted exactly (headers, query strings, JSON bodies) —
`plan/ntfy-api-reference.md` is the source of truth for the wire format.

## Quality gates

All of these must pass — CI enforces them:

```sh
mix format --check-formatted
mix credo --strict
mix test --warnings-as-errors
mix coveralls          # minimum 90% coverage
mix dialyzer
mix docs               # must be warning-free
```

## Live integration tests

`test/live/` runs against the real ntfy.sh and is excluded by default:

```sh
mix test --only live
```

Keep live tests few and gentle (random per-test topics, spaced requests) —
ntfy.sh has rate limits and we are guests. Live tests *detect* bugs; the
regression test that pins the fix must be a stub/Bypass test.

## Conventions worth knowing

- Options are validated with NimbleOptions schemas; unknown options must
  raise, never be silently dropped. Schemas self-document via
  `NimbleOptions.docs/1` interpolated into moduledocs.
- Parsing is lenient (unknown fields/events are preserved or tagged, never
  crashes); encoding is strict.
- Feature modules build request options and go through `ExNtfy.Client`;
  responses parse through `ExNtfy.Message.from_map/1`.
- Public functions carry `@spec` and `@doc`; true internals are
  `@moduledoc false`.
- Telemetry metadata never includes credentials or message contents.

## Reporting bugs

Include your Elixir/OTP versions, the ntfy server (ntfy.sh or self-hosted +
version), a minimal snippet, and expected vs. actual behavior. For wire-format
mismatches, the raw HTTP exchange (e.g. via `req_options: [plug: ...]` or a
proxy) is gold.

## Code of conduct

Be respectful and constructive in all interactions.
