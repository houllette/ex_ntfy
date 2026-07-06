# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
