# Phase 7 — WebSocket Transport (optional)

## Mission

Add `format: :ws` to `ExNtfy.Subscription`, subscribing via `GET /<topics>/ws` (reference
§2.1) using an **optional** `mint_web_socket` dependency. This phase is optional: the `/json`
stream already delivers everything WebSockets deliver. Build it for API completeness ("every
option") — but if priorities are tight, Phase 8 may ship first and this can land in a minor
release afterward.

## Prerequisites

Phases 1–6 complete. `ExNtfy.Subscription` passes its suite. Familiarity with
`Mint.HTTP`/`Mint.WebSocket` upgrade flow.

## Deliverables

- `{:mint_web_socket, "~> 1.0", optional: true}` in mix.exs. Guard the transport with
  `Code.ensure_loaded?(Mint.WebSocket)` and raise a clear error
  ("add :mint_web_socket to your deps to use format: :ws") when missing.
- `ExNtfy.Stream.WS` transport module driven by the same `Subscription` GenServer:
  - URL scheme http(s) → ws(s); same topic path + query builder from Phase 5 (filters,
    `since`, etc. all apply).
  - Auth: `Authorization` header works on the upgrade request; `auth_via: :query` also
    supported (this is the canonical use case for `?auth=`).
  - Each text frame is one JSON message object (same schema) → `Message.from_map/1`.
  - Reuse ALL Phase 6 semantics: keepalive watchdog, reconnect + `since=<last id>` resume,
    owner monitoring, handler/message-passing/stream consumption. The transport is the only
    thing that changes — refactor `Subscription` to a transport callback boundary if Phase 6
    didn't already shape it that way (record in NOTES.md).
  - Respond to WS ping frames with pong (Mint.WebSocket handles frame encode; the GenServer
    must reply); close frames → normal disconnect → reconnect flow.

## Test plan (TDD — write these first)

Test server: Bypass alone can't upgrade; use a minimal Bandit + Plug + WebSockAdapter echo
app started in test (add `{:bandit, "~> 1.0", only: :test}`, `{:websock_adapter, "~> 0.5",
only: :test}`).

1. Upgrade request path/query: `/<topics>/ws?since=...&priority=...` built from the shared
   options builder.
2. Text frames parse to `%Message{}` and deliver through the existing consumption styles
   (run the Phase 6 delivery assertions parameterized over `format: :ws`).
3. Ping → pong; server close → reconnect with `since=<last id>`.
4. Missing optional dep: with the transport module's guard mocked to "unavailable", a clear
   `ArgumentError`/`RuntimeError` fires at `subscribe/2` time (not deep in the process).
5. `auth_via: :query` end-to-end against the test server (assert the `auth` param the server
   received decodes to the Authorization value).

## Definition of Done

- [ ] `format: :ws` documented in `Subscription` moduledoc incl. the optional-dependency note
- [ ] Phase 6 suite still fully green (transport refactor must not regress)
- [ ] Quality gates pass (dialyzer with optional dep both present and absent — CI job for
      the "absent" compile check is a nice-to-have; at minimum verify locally)
- [ ] CHANGELOG updated; NOTES.md written

## Out of scope

Binary frames (ntfy sends text), compression extensions, proxies.
