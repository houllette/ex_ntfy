# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `format: :ws` — WebSocket subscriptions (`GET /<topics>/ws`) via the
  **optional** `:mint_web_socket` dependency, with identical semantics to the
  HTTP stream formats (reconnect/resume, watchdog, all consumption styles);
  `ExNtfy.Subscription` now drives connections through a
  `Subscription.Transport` boundary
- `ExNtfy.subscribe/2`, `unsubscribe/1`, and `ExNtfy.Subscription` — long-lived
  streaming subscriptions over `/json` (plus `/sse` and `/raw` via `format:`),
  with automatic reconnect (exponential backoff + jitter, `since=<last id>`
  resume), a keepalive watchdog (`idle_timeout:`), owner monitoring, and
  `[:ex_ntfy, :subscription, ...]` telemetry
- `ExNtfy.Handler` — optional behaviour for callback-style consumption inside
  the subscription process (supervision-tree friendly)
- `ExNtfy.stream/2` — a lazy `Enumerable` of messages that blocks the caller
  and halts cleanly
- `ExNtfy.Stream.NDJSON`, `ExNtfy.Stream.SSE`, `ExNtfy.Stream.Raw` — pure
  incremental parsers with partial-line buffering across arbitrary chunk
  boundaries
- `ExNtfy.poll/2` and `poll!/2` — one-shot retrieval of cached messages
  (`GET /<topics>/json?poll=1`) with the full `since`/`scheduled`/filter
  surface, multi-topic support, ndjson parsing (unparsable lines skipped with
  a warning), and `[:ex_ntfy, :poll, ...]` telemetry spans
- `ExNtfy.Subscribe.Options` — subscribe option schema and URL builder
  (`path/2`, `topics_segment/1`, `to_query/1`), shared infrastructure for
  polling and the upcoming streaming subscriptions
- `ExNtfy.publish_file/3` and `publish_file!/3` — binary attachment uploads
  (`PUT /<topic>`) accepting iodata, chunk streams, or `{:file, path}`
  (streamed from disk, filename defaulting to the basename), with all publish
  options riding along as headers
- `ExNtfy.update/4`, `clear/3`, and `delete/3` — the sequence-ID notification
  lifecycle: republish with the same sequence ID, `PUT /<topic>/<seq>/clear`,
  and `DELETE /<topic>/<seq>`
- Topic names and sequence IDs are percent-escaped in request paths
- `ExNtfy.publish/3`, `publish!/3`, `publish_raw/3`, and `trigger/2` —
  publishing with full option coverage (title, priority, tags, markdown,
  delay, click, icon, attach, filename, actions, email, call, sequence_id,
  cache, firebase, unified_push, template, poll_id), delegating to
  `ExNtfy.Publisher`
- `ExNtfy.Publish.Options` — one NimbleOptions schema validating publish
  options and encoding them as JSON body fields, canonical `X-` headers
  (RFC 2047 for non-ASCII values), or query parameters
- `ExNtfy.Action.to_json_map/1` and `to_short/1` — outgoing action-button
  encoding (JSON and ntfy short format), round-tripping with `from_map/1`
- Telemetry: `[:ex_ntfy, :publish, :start | :stop | :exception]` span events
  with `%{topic, base_url}` metadata
- `ExNtfy.Client` — Req-based HTTP client with `new/1` and `request/2`,
  Basic/Bearer authentication via header or `?auth=` query parameter, and a
  `req_options` escape hatch
- `ExNtfy.Config` — option resolution with per-call > application config >
  defaults precedence, validated with NimbleOptions
- `ExNtfy.Error` — exception type covering ntfy JSON errors, plain-text/empty
  error bodies, and transport failures
- `ExNtfy.Message`, `ExNtfy.Action`, `ExNtfy.Attachment` — lenient parsing of
  the ntfy message schema (`from_map/1`, `from_json/1`), retaining the raw map
- Project scaffolded
