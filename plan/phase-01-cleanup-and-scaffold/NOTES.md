# Phase 1 Notes — Surprises & Deviations

## Deviations from the plan

- **Latest-versions directive (user, mid-phase):** The user asked for the absolute latest
  versions of everything. Result: `elixir: "~> 1.20"` (plan said `~> 1.15`), `req: "~> 0.6"`
  (plan said `~> 0.5`), `ex_doc: "~> 0.40"` (plan said `~> 0.34`). All other constraints from
  the plan were already the latest series (nimble_options 1.1.1, bypass 2.1.0, credo 1.7.19,
  dialyxir 1.4.7, excoveralls 0.18.5). Lockfile fully re-locked with `mix deps.update --all`.
- **CI matrix:** Plan said "two newest Elixir versions on OTP 26/27". With the requirement now
  `~> 1.20`, only Elixir 1.20 qualifies, so the matrix is Elixir 1.20 on OTP 28 and 29 (the
  two newest OTP majors) instead.
- **`preferred_cli_env` → `def cli`:** The project-level `preferred_cli_env` key the plan
  called for is deprecated (warns on Elixir 1.20). Used `def cli do [preferred_envs: ...]`
  instead — same effect, no deprecation warning.
- **`.github/ISSUE_TEMPLATE/bug_report.md`:** Plan said keep `ISSUE_TEMPLATE/` as-is, but the
  bug template had OpenAPI-generator fields (generator version, spec paste section) which
  tripped the Definition-of-Done grep. Replaced them with ExNtfy/ntfy-server fields.

## Surprises / things later phases should know

- **cowlib CVEs (test-only):** `mix hex.audit` flags cowlib 2.18.0 — EEF-CVE-2026-43966
  (MEDIUM, HTTP response splitting) and EEF-CVE-2026-43969 (LOW, cookie header injection).
  cowlib 2.18.0 is the *newest* release as of 2026-07-05; no patched version exists yet.
  It is a transitive dep of bypass → cowboy, `only: :test`, so there is zero runtime/prod
  exposure. Re-check `mix hex.audit` in later phases and bump when a fix ships.
- **Coverage is 0% right now:** `lib/ex_ntfy.ex` has no relevant (executable) lines, and
  `ExNtfy.TestHelpers.req_stub/1` is not yet exercised (first consumer arrives in Phase 2).
  `mix coveralls` passes because no `minimum_coverage` threshold is configured; consider
  adding one once Phase 2 lands real code.
- **`ExNtfy.TestHelpers.req_stub/1`** stubs `Req.Test` under the name `ExNtfy` and returns
  `[plug: {Req.Test, ExNtfy}]` — Phase 2's client should accept these as request options.
  The `Plug.Conn.t()` spec compiles only in `:test` env (plug comes transitively via bypass),
  which is fine since `test/support` is only in `elixirc_paths` for `:test`.
- Local toolchain: Elixir 1.20.2 / OTP 29. Dialyzer PLT at `priv/plts/ex_ntfy.plt`
  (gitignored); first full build was fast (~2 min including deps PLT).
