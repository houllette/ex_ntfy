# Phase 4 — Attachment Uploads & Notification Lifecycle

## Mission

Complete the publish surface: binary attachment uploads (`PUT /<topic>` with file body) and
the sequence-ID lifecycle — updating, clearing, and deleting delivered notifications
(reference §1.4, §1.7).

## Prerequisites

Phases 1–3 complete: `ExNtfy.publish/3` with full options passes its suite. Read reference
§1.4 and §1.7.

## Public API

```elixir
# Upload a binary/file as attachment. body: iodata | {:file, path} | Enumerable (stream)
ExNtfy.publish_file(topic, body, opts \\ [])   # + publish_file!/3
# honors :filename, :message (X-Message header rides along), and ALL Phase-3 options
# via the header path (title, priority, tags, delay, click, actions, ...)

# Lifecycle (sequence_id = a previous message's id, or caller-chosen sequence id)
ExNtfy.update(topic, sequence_id, message, opts \\ [])  # publish with sequence reuse
ExNtfy.clear(topic, sequence_id, opts \\ [])            # PUT /<topic>/<seq>/clear
ExNtfy.delete(topic, sequence_id, opts \\ [])           # DELETE /<topic>/<seq>
```

Implementation notes:

- `publish_file/3` uses the **header path** from Phase 3 (`Publish.Options` header encoding)
  since the body is the file. `{:file, path}` should stream from disk (Req supports iodata
  and enumerable bodies); don't read whole files into memory. Filename defaults to
  `Path.basename(path)` for `{:file, _}`.
- `update/4` is sugar over `publish/3` with `:sequence_id` set — implement it that way
  (JSON path, `sequence_id` field). Document the two ntfy idioms: reuse a returned message
  `id`, or pick your own sequence ID up front.
- `clear/3` uses `PUT` (alias endpoint `/read` exists; expose via `opts[:via] == :read`? No —
  keep one canonical endpoint, mention the alias in docs only).
- `delete/3` uses `DELETE /<topic>/<seq>`. The `GET .../delete` and `GET .../clear` forms are
  for header-limited clients; an SDK has full HTTP, so don't expose them.
- Responses: lifecycle endpoints return event JSON (`message_clear` / `message_delete`) —
  parse with `ExNtfy.Message.from_map/1` like everything else.
- Attachment responses include the `attachment` object; assert `ExNtfy.Attachment` fields
  populate (`type`/`size`/`expires` present for uploads).

## Test plan (TDD — write these first)

Req.Test request-shape tests:

1. `publish_file/3` with iodata: `PUT /<topic>`, body byte-identical, `X-Filename` header set
   when `:filename` given.
2. `publish_file/3` with `{:file, path}` (tmp fixture file): body matches file content;
   filename defaults to basename; explicit `:filename` overrides.
3. `publish_file/3` carries Phase-3 options as headers (spot-check `:title` incl. RFC 2047
   case, `:message`, `:priority`, `:delay`).
4. Upload response with full `attachment` object parses into `%ExNtfy.Attachment{}` with
   `type`, `size`, `expires`.
5. `update/4` sends `sequence_id` in JSON body; returned message carries it.
6. `clear/3` → `PUT /<topic>/<seq>/clear`, no body; response `event: :message_clear` with
   `sequence_id`.
7. `delete/3` → `DELETE /<topic>/<seq>`; response `event: :message_delete`.
8. Error paths: 413 (attachment too large) and 429 map to `%ExNtfy.Error{}`.
9. Sequence IDs with URL-meaningful characters are path-escaped (test `seq id/​?x`-style
   input → assert escaped path). Same for topic names everywhere (add the topic-escaping
   test here if Phase 3 didn't).

## Definition of Done

- [ ] All test-plan items green, written test-first
- [ ] `ExNtfy` moduledoc gains Attachments + Lifecycle sections with examples (incl. the
      "publish then update by returned id" idiom)
- [ ] Quality gates pass; CHANGELOG updated; NOTES.md written

## Out of scope

Downloading attachments from messages (users get `attachment.url`; a convenience downloader
can be a post-1.0 idea — note it in NOTES.md if you feel strongly). Subscribing (next phases).
