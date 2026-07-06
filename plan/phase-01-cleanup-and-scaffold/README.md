# Phase 1 — Cleanup & Project Scaffold

## Mission

Turn this repo from an unused OpenAPI-generator template into a clean, hand-written Elixir
library project named `ex_ntfy`, with dependencies, test infrastructure, quality tooling, and
CI in place — but **no SDK features yet**. Later phases assume `mix test`, `mix credo
--strict`, and `mix dialyzer` all pass on a skeleton project.

## Prerequisites

None — this is the first phase. Verify you're starting from the template state: there is no
`mix.exs` at the repo root and an `.openapi-generator/` directory exists. (If `mix.exs`
already exists, this phase was already run; stop and re-read the plan.)

## Step 1 — Delete template cruft

The repo was created from an "Elixir SDK Generator" template that generated Tesla-based SDKs
from OpenAPI specs. ntfy has no OpenAPI spec and we're hand-writing a Req-based SDK, so all of
the following are dead weight. Delete:

- `openapi-spec.yaml`, `generator-config.yaml`, `.openapi-generator/` (whole dir),
  `.openapi-generator-ignore`, `setup.json`
- `scripts/` (whole dir — setup/regenerate/post-generate/validate-spec/cleanup-template all
  serve the generator; `publish.sh` is replaced by standard `mix hex.publish` in Phase 8)
- `QUICKSTART.md` (template-specific)
- `.github/workflows/*.yml.disabled` and `.github/workflows/README.md` (replaced below)
- `test/support/test_case.ex`, `test/support/mock_server.ex`, `test/support/fixtures.ex`,
  `test/unit/`, `test/integration/` (Tesla/Mox-based; we rebuild on Req.Test below)
- `config/` (whole dir — a library should not ship compile-time config; runtime configuration
  happens via the host app's `config :ex_ntfy` and per-call options)

Keep: `.github/ISSUE_TEMPLATE/`, `.github/pull_request_template.md`, `.formatter.exs` (review
contents), `CHANGELOG.md` (reset contents), `CONTRIBUTING.md` (trim generator references —
quick pass now, full rewrite in Phase 8), `README.md` (gut it now — replace with a short
"under construction" stub naming the project and goal; full README in Phase 8).

## Step 2 — Scaffold the Mix project

Create by hand (don't run `mix new` over the existing repo; it will fight existing files):

- `mix.exs` — app `:ex_ntfy`, version `0.1.0`, `elixir: "~> 1.15"`, no `mod:` (no application
  callback), `elixirc_paths: ["lib", "test/support"]` for `:test` env only. Include package
  metadata (description, licenses `["MIT"]`, links) and `docs` config for ExDoc.
- `lib/ex_ntfy.ex` — module with `@moduledoc` describing the SDK; no functions yet.
- `LICENSE` (MIT).
- `.gitignore` for Elixir (`/_build`, `/deps`, `/cover`, `/doc`, `erl_crash.dump`, `*.ez`,
  `.elixir_ls/`, `/priv/plts/`).

Dependencies:

```elixir
{:req, "~> 0.5"},
{:nimble_options, "~> 1.1"},
# dev/test
{:bypass, "~> 2.1", only: :test},
{:credo, "~> 1.7", only: [:dev, :test], runtime: false},
{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
{:excoveralls, "~> 0.18", only: :test},
{:ex_doc, "~> 0.34", only: :dev, runtime: false}
```

(No Jason dep needed — Req brings JSON handling; use `Jason` transitively in tests if
convenient, or `JSON` from stdlib on Elixir ≥ 1.18. No Mox, no Tesla, no Finch.)

Configure in `mix.exs`: `test_coverage: [tool: ExCoveralls]`, `preferred_cli_env` for
coveralls tasks, dialyzer PLT path under `priv/plts/` (gitignored).

## Step 3 — Test infrastructure

- `test/test_helper.exs` — `ExUnit.start()`.
- `test/support/` — keep minimal; add helpers only when a later phase needs them. A good
  starter: `ExNtfy.TestHelpers` with a `req_stub(fun)` convenience wiring `Req.Test` stubs and
  returning opts to pass into the SDK (later phases refine this once `ExNtfy.Client` exists,
  e.g. plugging `plug: {Req.Test, ExNtfy}` through client options).
- One smoke test asserting the project compiles and `ExNtfy` module exists (placeholder so
  `mix test` is green and coverage tooling runs).

## Step 4 — Quality tooling & CI

- `.formatter.exs` — plain `inputs: ["{mix,.formatter}.exs", "{lib,test}/**/*.{ex,exs}"]`.
- `.credo.exs` — `mix credo gen.config`, strict mode; keep defaults unless noisy.
- `.github/workflows/ci.yml` — on push/PR: checkout, `erlef/setup-beam` matrix (two newest
  Elixir versions on OTP 26/27), deps cache, `mix deps.get`, `mix format --check-formatted`,
  `mix credo --strict`, `mix test --warnings-as-errors`, `mix coveralls`, plus a separate
  cached `mix dialyzer` job.
- Reset `CHANGELOG.md` to Keep-a-Changelog skeleton with an `[Unreleased]` section noting
  "Project scaffolded".

## Test plan (TDD)

This phase is scaffolding, so the "tests" are the gates themselves. In order:

1. Write the smoke test (`test/ex_ntfy_test.exs`) first — it fails because nothing compiles.
2. Make it pass by completing Step 2.
3. Get all four quality gates green locally, then confirm CI is green.

## Definition of Done

- [ ] Every file listed in Step 1 is deleted; `git grep -il "openapi\|tesla\|mustache"`
      returns nothing outside `plan/` and `CHANGELOG.md`
- [ ] `mix deps.get && mix test` green; `mix format --check-formatted`, `mix credo --strict`,
      `mix dialyzer`, `mix coveralls` all pass
- [ ] CI workflow runs and passes on GitHub
- [ ] README stub, LICENSE, CHANGELOG reset committed
- [ ] `plan/phase-01-cleanup-and-scaffold/NOTES.md` written (surprises, deviations)

## Out of scope

Any actual HTTP calls or SDK API surface — that starts in Phase 2.
