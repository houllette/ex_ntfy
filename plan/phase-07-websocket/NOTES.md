# Phase 7 Notes — Decisions & Surprises

## The transport-boundary refactor (as the plan anticipated)

Phase 6 had coupled `Subscription` to Req's `into: :self`. This phase extracted
`ExNtfy.Subscription.Transport` — three callbacks (`connect/3`,
`handle_message/2` → `{:data, units, conn} | {:closed, units, reason} |
{:error, reason} | :unknown`, `close/1`) — with the existing logic moving
verbatim into `ExNtfy.Subscription.HTTPTransport`. The Phase 6 suite passed
unchanged after the refactor. Everything above the boundary (reconnect/backoff,
`since` resume, idle watchdog, owner monitoring, delivery styles, telemetry) is
shared; a format now selects a `{transport, parser}` pair, and `ExNtfy.Stream.WS`
implements *both* contracts (frames need no line reassembly, so its parser is
just `Message.from_json/1` per text frame).

Error fate convention at the boundary: `%Error{reason: nil}` from `connect/3`
means HTTP-level rejection → fatal; anything else is transport-level →
reconnect flow. The WS non-101 upgrade path parses the rejection body JSON, so
`{:down, %Error{code: 40301, http: 403}}` comes out fully populated.

## Decisions

- **Optional-dep guard**: `Stream.WS.ensure_available!/0` raises a clear
  `ArgumentError` (naming `:mint_web_socket`) from `build_config!` — i.e. at
  `subscribe/2` time in the caller, not inside the process. The checked module
  is read from the `:ws_dependency` app env (default `Mint.WebSocket`) purely
  so the async-unfriendly "dep missing" test can simulate absence
  (`subscription_ws_unavailable_test.exs`, `async: false`).
- **Compile-with-dep-absent**: all `Mint.WebSocket` references are runtime;
  `elixirc_options: [no_warn_undefined: [Mint.WebSocket]]` suppresses the
  undefined-module warning for consumers without the dep. (The plan suggested
  `xref: [exclude: ...]` — that spelling is deprecated in Elixir 1.20.)
  `Mint.HTTP` needs no exclusion: mint is always present via finch/req.
- **Ping→pong is handled inside the transport**, invisible to the GenServer;
  pings still reset the idle watchdog because any `{:data, ...}` (even with no
  payload units) does. Binary frames are ignored (ntfy sends text).
- **Upgrade await is a selective receive** on `:tcp`/`:ssl`-tagged messages
  only (bounded by `receive_timeout`, default 15 s), so owner-`DOWN` and timer
  messages queued during connect are not swallowed; `:unknown` stragglers from
  a previous canceled connection are dropped.
- Auth reuses `Client.encode_auth/2` (made public `@doc false`, with
  `Client.user_agent/0`) — the upgrade request carries the same
  `Authorization` header or `?auth=` param; the query test asserts the param
  base64url-decodes to the exact header value.

## Surprises / things later phases should know

- **Dialyzer false positive on `Mint.WebSocket.new/5`**: it can't track Mint's
  private conn state through the `Mint.WebSocket.stream/2` await loop and
  concludes the `{:ok, conn, websocket}` success can never match. Scoped
  `@dialyzer {:nowarn_function, finish_upgrade: 3}` with a comment; tests
  assert the success path constantly.
- Bandit + WebSock made a pleasant test server (`test/support/ws_test_server.ex`):
  `start_supervised!` + `ThousandIsland.listener_info/1` for the random port;
  WebSock `handle_control/2` sees client pongs; pushing `{:ping, data}` frames
  works. None of the Bypass `:shutdown` trap issues from Phase 6 — no
  expectation verification.
- `websock_adapter` is at 0.6.x (plan said `~> 0.5`); bandit at 1.12,
  mint_web_socket 1.0.5 — latest everything per the standing preference.
- Coverage: 93.3% total; `stream/ws.ex` is 72.3% — the misses are deep error
  paths (upgrade timeout, mid-stream decode errors, send-frame failures, the
  `:wss` scheme arm) that would need heavy socket fault injection to reach.
- **cowlib CVEs still open** (EEF-CVE-2026-43966 MEDIUM / EEF-CVE-2026-43969
  LOW, test-only; 2.18.0 still newest as of 2026-07-05). Re-check next phase.
