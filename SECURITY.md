# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| 0.1.x   | ✅        |

## Reporting a vulnerability

Please **do not open a public issue** for security problems. Instead, report
privately via
[GitHub security advisories](https://github.com/houllette/ex_ntfy/security/advisories/new).

You can expect an acknowledgement within a week. Fixes ship as patch releases
with a CHANGELOG entry crediting the reporter (unless you prefer otherwise).

## Scope notes

- ExNtfy transmits whatever credentials you configure (`Authorization`
  header, or the `?auth=` query parameter when you opt into
  `auth_via: :query` — be aware query strings may appear in server logs).
- Telemetry events never include credentials or message contents.
- Topic names act as secrets on public ntfy instances; treat them like
  passwords and prefer authenticated self-hosted servers for sensitive use.
