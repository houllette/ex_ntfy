# Phase 4 Notes — Decisions & Surprises

## Decisions the plan left open

- **`{:file, path}` streams via `File.stream!(path, 64 * 1024)`** (64 KiB raw chunks) —
  Req sends enumerable bodies chunked, so large files never load into memory. The
  filename default is applied with `Keyword.put_new`, so an explicit `:filename` wins.
- **`publish_file/3` uses the Phase 3 header path unchanged** — `Options.to_headers/1`
  already covered every option (including `:message` for the text alongside the upload),
  so the new function is just `PUT` + body + headers; no Options changes were needed.
- **Lifecycle endpoints accept client options only.** `clear/3` and `delete/3` pass
  `opts` straight to `Client.new/1`; publish options make no sense there, and an
  accidental `title:` raises `NimbleOptions.ValidationError` in Config rather than being
  dropped.
- **Only canonical endpoints exposed**, per the plan: `PUT .../clear` (not the `/read`
  alias) and `DELETE /<topic>/<seq>` (not the `GET .../delete`/`GET .../clear` forms,
  which exist for header-limited clients).
- **`update/4` is literal sugar**: `publish(topic, message, Keyword.put(opts,
  :sequence_id, sequence_id))` — it inherits the JSON path, validation, telemetry, and
  both docs idioms (reuse a returned message `id`, or pick a sequence ID up front).
- **All new functions reuse the `[:ex_ntfy, :publish, ...]` telemetry span**, including
  `clear`/`delete` — they are publishes server-side (they emit `message_clear`/
  `message_delete` events), and one event namespace keeps handlers simple.
- **Path escaping centralized** in `path_segment/1` (`URI.encode/2` with
  `char_unreserved?`); `topic_path/1` now uses it too, and both topic and sequence-ID
  escaping are asserted in tests (`"seq id/?x"` → `seq%20id%2F%3Fx`).

## Surprises / things later phases should know

- **Req's plug adapter handles enumerable request bodies** — the `{:file, path}` stream
  test (200 KB random bytes) worked against `Req.Test` with no special handling; the
  whole Phase went green on the first run after implementation.
- `ExUnit`'s `@tag :tmp_dir` provides per-test scratch dirs for the file fixtures — no
  manual cleanup needed.
- **cowlib CVEs still open** (EEF-CVE-2026-43966 MEDIUM / EEF-CVE-2026-43969 LOW,
  test-only via bypass → cowboy; 2.18.0 still newest as of 2026-07-05). Re-check
  `mix hex.audit` next phase.
- Coverage after this phase: 97.7% (gate is 90%).

## Post-1.0 idea (from "out of scope")

A convenience attachment downloader (`ExNtfy.download_attachment(message, path)` fetching
`message.attachment.url` with the client's auth) would round out the story, but it's
plain HTTP GET the user can do with Req directly — not worth API surface before 1.0.
