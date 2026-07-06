# Phase 8 Notes — Release State & Known Gaps

## Release state: one `git tag v0.1.0 && git push --tags` away

- **Phase 7 `:ws` SHIPPED** — the optional-phase caveat in release notes is moot;
  `format: :ws` is in 0.1.0 behind the optional `mint_web_socket` dep.
- CHANGELOG shows `0.1.0 — 2026-07-05`. Version in mix.exs already `0.1.0`.
- `mix hex.build` audited: tarball contains only `lib/`, `mix.exs`, `README.md`,
  `CHANGELOG.md`, `LICENSE`, `.formatter.exs` — no `plan/`, `test/`, `guides/`, or CI
  files. `mint_web_socket` correctly listed optional.
- `mix hex.publish --dry-run` verified locally (needs an interactive owner selection —
  piping `1` works; the CI workflow with `HEX_API_KEY` won't prompt).
- `.github/workflows/publish.yml`: full gates then publish on `v*` tags;
  `workflow_dispatch` with a `dry_run` input (default **true**) for rehearsals.
  **Maintainer to-dos before tagging**: set the `HEX_API_KEY` repo secret; optionally run
  the dispatch dry-run once in GitHub.
- CI gained a `mix docs --warnings-as-errors` step (in the Dialyzer job, which already
  runs the dev env).

## Live suite results

- `test/live/live_test.exs`, tagged `:live`, excluded via `ExUnit.configure(exclude:
  [:live])`; run with `mix test --only live`. Three tests, < 20 requests total, random
  `ex-ntfy-ci-*` topic per test, 500 ms pacing.
- **Passed twice consecutively against ntfy.sh with zero SDK bugs found** — publish
  (minimal + kitchen-sink with actions), poll with priority-OR/tags-AND filters, streaming
  subscribe, and the full update/clear/delete lifecycle observing
  `message_clear`/`message_delete` events all behaved exactly as the stub suites predicted.
- One test-side fix: ntfy.sh's cache is eventually consistent (a poll immediately after a
  publish can miss it) — the poll test retries up to 8×1 s (`poll_until/4`). Not an SDK
  issue; no `Cache-Control` knob applies.
- Deliberately **not** exercised live: `email:`/`call:` (would send real e-mail/calls),
  `delay:` (≥10 s minimum breaks fast assertions), binary uploads (rate-limit friendliness).

## Docs decisions

- Hidden from docs (`@moduledoc false`, prose kept as comments): the three stream parsers,
  `Subscription.Transport`, `Subscription.HTTPTransport`. Public surface reads as four
  groups: Publishing / Polling & Subscribing / Types / Client & Config, with `ExNtfy` as
  the landing page. `Stream.WS` stays documented (users need the optional-dep story).
- Deviation from plan: `Publish.Options` and `Subscribe.Options` stay **documented** —
  they hold the canonical NimbleOptions-generated option tables that the facade and guides
  link to; hiding them would orphan those references.
- Guides: `guides/publishing.md` (every publish option demonstrated) and
  `guides/subscriptions.md` (three consumption styles, supervision, reconnect semantics,
  transports), wired via `extras` and grouped under "Guides".
- All 22 README + guide code blocks are machine syntax-checked
  (`Code.string_to_quoted!`); semantics covered by the live suite.
- ExDoc gotcha: CHANGELOG is an extra, so backticked references to hidden modules in old
  entries produce warnings — de-linked them.

## Known gaps / post-1.0 ideas (carried forward)

- Attachment downloader convenience (Phase 4 note) — users have `message.attachment.url`.
- Optional live CI job (`workflow_dispatch`) was considered and skipped: the suite is
  documented in CONTRIBUTING and cheap to run locally; a scheduled job against a public
  service invites flakes and rate-limit noise.
- **cowlib CVEs still open** (EEF-CVE-2026-43966 MEDIUM / EEF-CVE-2026-43969 LOW,
  test-only via bypass → cowboy; 2.18.0 still newest as of 2026-07-05). Doesn't ship in
  the package (test-only dep) — safe to release; keep watching upstream.
- ntfy docs integrations PR (https://docs.ntfy.sh/integrations/) — manual, post-release.
