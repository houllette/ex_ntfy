# ntfy HTTP API Reference (verified)

Distilled from the upstream docs source (`github.com/binwiederhier/ntfy` → `docs/publish.md`,
`docs/subscribe/api.md`) in **July 2026**. This is the ground truth for the SDK's feature
surface. Live docs: https://docs.ntfy.sh/publish/ and https://docs.ntfy.sh/subscribe/api/.

All parameter names (headers and query params) are **case-insensitive**, and almost every
header can also be passed as a query parameter of the same name/alias.

---

## 1. Publishing

### 1.1 Endpoints

| Method & path | Purpose |
|---|---|
| `PUT\|POST /<topic>` | Publish; request body = message text (or binary attachment) |
| `POST /` | Publish as JSON; body = JSON document (topic inside body) |
| `PUT\|POST /<topic>/<sequence_id>` | Publish/update with an explicit sequence ID in the path |
| `GET /<topic>/publish` (aliases `/send`, `/trigger`) | Webhook-style publish; all options as query params; empty message defaults to `"triggered"` |
| `PUT\|GET /<topic>/<sequence_id>/clear` (alias `/read`) | Clear (mark read + dismiss) a delivered notification |
| `DELETE /<topic>/<sequence_id>`, or `GET /<topic>/<sequence_id>/delete` | Delete a notification from clients |

Successful publish returns the created message as JSON (same schema as §2.4), e.g.
`{"id":"xE73Iyuabi","time":1673542291,"expires":1673585491,"event":"message","topic":"mytopic","message":"..."}`.

**Topic names:** letters, numbers, `_`, `-`; max 64 chars. Treated as a secret/password.

### 1.2 Publish headers (complete list, with aliases)

| Canonical header | Aliases | Value / notes |
|---|---|---|
| `X-Message` | `Message`, `m` | Message body (alternative to request body) |
| `X-Title` | `Title`, `t` | Title. UTF-8 in header values must be RFC 2047-encoded (`=?UTF-8?B?...?=`) |
| `X-Priority` | `Priority`, `prio`, `p` | `1`/`min`, `2`/`low`, `3`/`default`, `4`/`high`, `5`/`max`/`urgent` |
| `X-Tags` | `Tags`, `Tag`, `ta` | Comma-separated tags; known emoji shortcodes render as emoji |
| `X-Delay` | `Delay`, `X-At`, `At`, `X-In`, `In` | Scheduled delivery: unix timestamp, duration (`30m`, `3h`, `2 days`), or natural language (`10am`, `tomorrow, 3pm`). Server limits: ≥ 10 s, ≤ 3 days (configurable) |
| `X-Actions` | `Actions`, `Action` | Action buttons: JSON array **or** short format (§1.5) |
| `X-Click` | `Click` | URL opened on notification tap (`http(s):`, `mailto:`, `geo:`, `ntfy://`, app deep links...) |
| `X-Attach` | `Attach`, `a` | Attach a file **by URL** (server does not download it; clients do) |
| `X-Markdown` | `Markdown`, `md` | `true`/`1`/`yes` — message body is Markdown (web app renders it) |
| `X-Icon` | `Icon` | JPEG/PNG URL used as the notification icon (Android) |
| `X-Filename` | `Filename`, `file`, `f` | Attachment filename override (uploads and URL attachments) |
| `X-Email` | `X-E-Mail`, `Email`, `E-Mail`, `mail`, `e` | Forward to e-mail address, or `yes` = account's verified address |
| `X-Call` | `Call` | Phone call with message read out; phone number or `yes` (verified number; paid tier on ntfy.sh) |
| `X-Sequence-ID` | `Sequence-ID`, `SID` | Sequence ID for update/clear/delete lifecycle (§1.7) |
| `X-Cache` | `Cache` | `no` — don't cache server-side (delivered only to live subscribers; no `expires` in response) |
| `X-Firebase` | `Firebase` | `no` — don't forward to FCM (Android instant delivery only via ntfy connection) |
| `X-UnifiedPush` | `UnifiedPush`, `up` | `1` — UnifiedPush mode (implies no-Firebase; binary body base64-encoded). Only for UP apps |
| `X-Poll-ID` | `Poll-ID` | Internal (iOS instant notifications). Support pass-through, don't surface prominently |
| `X-Template` | `Template`, `tpl` | Templating (§1.6): `yes`/`1` = inline; `github`/`grafana`/`alertmanager` = pre-defined; other = custom server-side template name |
| `Content-Type` | — | `text/markdown` enables Markdown (same as `X-Markdown`) |
| `Authorization` | — | See §3 |

### 1.3 JSON publish (`POST /`) body fields

`topic` (required), `message`, `title`, `tags` (string array), `priority` (int 1–5),
`actions` (array of objects, §1.5), `click`, `attach` (URL), `markdown` (bool), `icon`,
`filename`, `delay` (string), `email`, `call`, `sequence_id`.

Header/query-only options (**not** JSON fields): `cache`, `firebase`, `unified_push`,
`template`, `poll_id` — send them as headers even on a JSON publish.

### 1.4 Attachments

- **Upload:** `PUT /<topic>` with binary body + optional `X-Filename`. Any message body > 4096
  bytes is auto-converted to an attachment. ntfy.sh limits: ~2 MB/file (15 MB default
  self-hosted), expiry ~3 h. Response's `attachment` object carries `name/url/type/size/expires`.
- **By URL:** `X-Attach: <url>` — no size limit server-side; only `name` + `url` set in response.
- `X-Message` can carry the notification text alongside an upload (body is the file).

### 1.5 Action buttons (max 3)

Two encodings: **JSON array** (used in JSON publish and in `X-Actions` if it starts with `[`)
and **short format** (`X-Actions: action1; action2`, comma-separated key-values, `label=`
etc.; values with `,`/`;` need single/double quotes).

| Action | Required fields | Optional fields |
|---|---|---|
| `view` | `label`, `url` | `clear` (bool, default false) |
| `broadcast` (Android) | `label` | `intent` (default `io.heckel.ntfy.USER_ACTION`), `extras` (string map; short format: `extras.<key>=<val>`), `clear` |
| `http` | `label`, `url` | `method` (**default POST**), `headers` (string map; short format `headers.<name>=<val>`), `body`, `clear` |
| `copy` | `label`, `value` | `clear` |

### 1.6 Templating (`X-Template` / `?template=`)

Body is arbitrary JSON (e.g. a GitHub/Grafana/Alertmanager webhook payload); ntfy renders
message/title/priority from Go templates:

- `template=yes|1` — **inline**: `message`/`title`/`priority` params themselves are Go templates
  evaluated against the JSON body.
- `template=github|grafana|alertmanager` — **pre-defined** server templates.
- `template=<name>` — **custom** template file on the server (`/etc/ntfy/templates/<name>.yml`).

SDK implication: this path needs a *raw body + query/header params* publish mode (the body is
NOT the ntfy JSON publish schema).

### 1.7 Update / clear / delete (sequence IDs)

Messages sharing a `sequence_id` form a sequence; clients apply the latest state.

- **Update:** publish again with the same sequence ID — via path `POST /<topic>/<seq>` or
  header `X-Sequence-ID`. A message's own `id` can serve as the sequence ID for follow-ups.
- **Clear:** `PUT|GET /<topic>/<seq>/clear` (alias `/read`) → emits `message_clear` event.
- **Delete:** `DELETE /<topic>/<seq>` or `GET /<topic>/<seq>/delete` → emits `message_delete`.
- Server storage is append-only; history remains. Deleted sequences revive if republished.

### 1.8 Limits (ntfy.sh defaults — surface in docs, don't hard-code)

Message ≤ 4096 bytes (else auto-attachment); ~60 requests burst, refill 1/5 s; 250
messages/day; e-mail ≤ 5/day; attachment 2 MB / 20 MB total; 30 open subscriber connections
per visitor. Errors: HTTP 4xx/5xx with JSON body `{"code": 42901, "http": 429, "error":
"...", "link": "..."}` (429 = rate limit / `too many requests`).

---

## 2. Subscribing

### 2.1 Endpoints

`GET /<topic>/json` (recommended; `Content-Type: application/x-ndjson`, one JSON object per
line) · `GET /<topic>/sse` (EventSource format) · `GET /<topic>/raw` (message body only, one
per line; empty lines = keepalive; no metadata) · `GET /<topic>/ws` (WebSocket; JSON objects,
same schema as `/json`).

**Multiple topics:** comma-separated in the path: `/topic1,topic2,topic3/json`.

### 2.2 Query params / headers (complete list, with aliases)

| Param | Aliases | Meaning |
|---|---|---|
| `poll` | `X-Poll`, `po` | `1` — return cached messages then close (no long-lived connection). Combines with everything below; default window `since=all` |
| `since` | `X-Since`, `si` | Return cached messages since: duration (`10m`), unix timestamp, message ID (exclusive-resume semantics), `all`, or `latest` (most recent message only) |
| `scheduled` | `X-Scheduled`, `sched` | `1` — include not-yet-delivered scheduled messages |
| `id` | `X-ID` | Filter: exact message ID |
| `message` | `X-Message`, `m` | Filter: exact message body match |
| `title` | `X-Title`, `t` | Filter: exact title match |
| `priority` | `X-Priority`, `prio`, `p` | Filter: comma-separated list, **any** match (logical OR); names or numbers |
| `tags` | `X-Tags`, `tag`, `ta` | Filter: comma-separated list, **all** must match (logical AND) |
| `auth` | — | See §3 |

Filters are case-insensitive.

### 2.3 Connection behavior

Server sends `open` event on connect, then `keepalive` events periodically (~every 45 s) on
otherwise-quiet connections. Clients should treat a prolonged silence (no message *or*
keepalive) as a dead connection and reconnect, resuming with `since=<last seen message id>`.

### 2.4 Message JSON schema

| Field | Type | Notes |
|---|---|---|
| `id` | string | Always present. Random message identifier |
| `time` | integer | Always present. Unix timestamp |
| `event` | string | `open`, `keepalive`, `message`, `message_clear`, `message_delete`, `poll_request` |
| `topic` | string | Always present; comma-separated list possible in `open` events |
| `expires` | integer | Unix timestamp of cache deletion; absent when published with `Cache: no` |
| `sequence_id` | string | Present on sequenced messages and on `message_clear`/`message_delete` events |
| `message` | string | Body; always present on `message` events |
| `title` | string | Optional |
| `tags` | string array | Optional |
| `priority` | integer 1–5 | Optional (3 = default) |
| `click` | string (URL) | Optional |
| `actions` | array | Optional; objects per §1.5 |
| `attachment` | object | Optional: `name` (req), `url` (req), `type`, `size`, `expires` (last three only for server-hosted uploads) |
| `icon` | string (URL) | Sent by server though omitted from the docs table — parse leniently |
| `content_type` | string | `text/markdown` when Markdown; parse leniently |

**Parse unknown fields leniently** (keep the raw map available); the server adds fields over time.

---

## 3. Authentication (publish & subscribe)

1. **Basic:** `Authorization: Basic base64(user:pass)`.
2. **Token:** `Authorization: Bearer tk_...` (tokens also work as Basic password with any/empty username).
3. **Query param:** `?auth=<base64url-without-padding of the FULL Authorization header value>`
   e.g. `base64url("Basic dGVzdHVzZXI6ZmFrZXBhc3N3b3Jk")` — needed for WebSocket/EventSource
   clients that can't set headers.

---

## 4. Cross-cutting SDK implications

- One canonical **options schema** (NimbleOptions) shared by publish paths; separate schema for
  subscribe/poll paths. Every row in the tables above must map to an option.
- Encoding helpers needed: priority atom→int, delay (DateTime/integer/string), tag list join,
  RFC 2047 for non-ASCII header values, action structs → JSON and → short format, auth →
  header or `?auth=` query token, boolean-ish server values (`"true"/"1"/"yes"`).
- Both directions share the message schema: publish *responses* and subscribe *events* parse
  into the same `ExNtfy.Message` struct.
