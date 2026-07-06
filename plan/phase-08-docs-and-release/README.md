# Phase 8 — Docs, Live Verification & Release Readiness

## Mission

Make ex_ntfy shippable: real README, polished ExDoc, an opt-in live integration suite
against ntfy.sh, and Hex packaging — ending with the repo one `mix hex.publish` away from
v0.1.0.

## Prerequisites

Phases 1–6 complete (Phase 7 optional — release notes must state whether `:ws` shipped).
Full quality gates green.

## Deliverables

### Documentation

- **README.md** (rewrite the Phase-1 stub): what/why, installation, quickstart for the big
  three (publish with options, poll, subscribe with a handler), auth setup, self-hosted
  `base_url` config, links to hexdocs. Keep it under ~150 lines; details live in hexdocs.
- **ExDoc polish:** `main: "ExNtfy"`, grouped modules (Publishing / Subscribing / Types /
  Internals via `groups_for_modules`), `@moduledoc false` on internals (Options builders,
  parsers) — the public surface should read small. Add two guides under `guides/` wired via
  `extras`: "Publishing cookbook" (every option demonstrated, incl. actions, templates,
  attachments, lifecycle) and "Subscriptions" (consumption styles, supervision, reconnect
  semantics).
- **CONTRIBUTING.md** rewrite: TDD workflow, quality gates, how the plan/ folders drove the
  build. **CHANGELOG.md**: collapse `[Unreleased]` into `0.1.0` with date.

### Live integration suite (opt-in)

`test/live/` tagged `@moduletag :live`, excluded by default in `test_helper.exs`
(`ExUnit.configure(exclude: [:live])`), run via `mix test --only live`:

1. Publish minimal + kitchen-sink (tags, priority, click, actions) to a random
   `ex-ntfy-ci-<random>` topic on ntfy.sh; assert returned `%Message{}`.
2. Poll the same topic with `since: :all` and find the published ids; filter checks
   (priority OR, tags AND).
3. Subscribe (json stream), publish from another process, assert delivery + keepalive
   survival; update/clear/delete lifecycle round-trip observing `message_clear` /
   `message_delete` events.
4. Respect ntfy.sh rate limits (reference §1.8): keep total requests small, sleep between
   publishes, single shared topic per run. Never run in default CI; optional manual
   workflow_dispatch job.

Fix any SDK bugs the live suite exposes (this is the point of the phase) — with a failing
Req.Test/Bypass regression test first, live tests only *detect*.

### Release mechanics

- `mix.exs` package block final: description, `licenses: ["MIT"]`, `links`, `files` list
  (exclude `plan/` from the Hex package!), `source_ref`.
- Version `0.1.0`; `mix hex.build` output inspected (no stray files); `mix docs` clean, no
  warnings; `mix hex.publish --dry-run` if available.
- `.github/workflows/publish.yml`: on `v*` tags, run full gates then `mix hex.publish
  --yes` with `HEX_API_KEY` secret. Do **not** publish in this phase — leave tagging to the
  maintainer; verify the workflow with a dry-run flag or `workflow_dispatch`.

## Test plan (TDD)

The unit suites exist; this phase adds: live tests above (written before any fixes they
provoke), a docs check (`mix docs 2>&1` free of warnings — add to CI), and a README
doctest-by-hand pass (every README snippet actually runs in `iex -S mix`).

## Definition of Done

- [ ] README + guides written; `mix docs` warning-free and added to CI
- [ ] Live suite passes against ntfy.sh (run at least twice, no flakes); excluded by default
- [ ] `mix hex.build` package contents audited (`plan/`, `test/`, CI files excluded)
- [ ] Publish workflow in place, untested-in-anger but dry-run-verified
- [ ] CHANGELOG shows `0.1.0`; final NOTES.md summarizing release state and known gaps
      (e.g. "Phase 7 :ws not shipped")

## Out of scope

Actually publishing to Hex (maintainer pushes the tag). Marketing, blog posts, ntfy docs PR
listing the SDK (worth doing manually later — https://docs.ntfy.sh/integrations/).
