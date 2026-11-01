# Jellyfin feasibility probes

Read `docs/research/jellyfin.md` for evidence, limits, safety, and remaining checks.
These tools are research utilities, not production application code.
They use Dart and Flutter test support from the existing Nix development shell.

```sh
nix develop --command flutter test tool/research/jellyfin --reporter expanded
nix develop --command dart analyze tool/research/jellyfin
nix develop --command dart run tool/research/jellyfin/probe.dart https://jellyfin.example.com
nix develop --command dart run tool/research/jellyfin/whole_set_fixture.dart
```

`probe.dart` reads public information by default.
It prints an explicit allowlist of fields, not raw private responses.
Every request has a total 20-second deadline from connection opening through body receipt. Expiry closes that request's HTTP client, including a body that keeps sending small chunks. The 4 MiB response limit still applies. Later cleanup requests use independent connections.
An optional `--secret-file` reads an ordinary-user session token from T3's private file.
It does not accept a token value as an argument or perform password login.
Do not use a server administrator API key.

Authenticated mode samples at most three visible books libraries and thirty media items from each.
This sampling cannot establish complete edition/file grouping.
`--allow-disposable-write` additionally enables synthetic display-preference round trips.
Each process owns one fresh namespace. It cannot write to a caller-selected item/client scope.
The write mode preserves defaults, retries identical values, and removes synthetic keys afterward.
Preference scope rows remain. No real progress, library metadata, or other user's records are modified.
Review the report before enabling writes.

`probe_test.dart` uses a synthetic loopback HTTP server to test the probe's safety and filtering.
`whole_set_fixture.dart` demonstrates full-set replacement counterexamples with synthetic file-backed state.
Its schedules serialize stale writes deliberately. They are not concurrent Jellyfin requests.
File reopening is not a Jellyfin restart or a process-restart test.

`public-evidence.json` is a captured public-only run.
`local-evidence.json` is captured model output. Neither contains private library data.
Neither file is a compatibility guarantee or an authenticated server result.
