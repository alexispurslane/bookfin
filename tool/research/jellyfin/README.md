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
An optional `--secret-file` reads a session token from T3's private file.
Alternatively, `--login-file <private-path>` reads a JSON object with nonempty `Username` and `Pw` strings.
Only the probe reads that file. Credentials never become command arguments or output.
Login uses `/Users/AuthenticateByName`. The returned token stays in memory.
The probe attempts `/Sessions/Logout` in cleanup and reports failure without printing the token.
Do not use both file options or pass a token value as an argument.
An administrator login permits read-only inspection, never research storage writes.
It cannot establish ordinary-user permissions or account isolation.

Authenticated mode samples at most three visible books libraries and thirty media items from each.
This sampling cannot establish complete edition/file grouping.
`--inspect-media` also requests separate counts and samples for `AudioBook`, `Audio`, `Book`, and `Folder`.
For each sampled library it inspects at most two distinct containers of each media type, their immediate siblings, chapters, and read-only playback information.
For each file it requests bytes 0–63 and 64–127 from both `/File` and `/Download`.
Each response has a 64-byte body ceiling and the same total 20-second deadline.
Requests that exceed the ceiling, fail, or time out are reported as refused reads, not proof of range support.
No returned media bytes are printed or saved. Downloads can add Jellyfin activity-log entries.
The probe reads item user data before and after these requests; it never reports playback progress.
An administrator inspection also reads the installed plugin list and prints only the Enhanced version and status.
The largest inspection has three library samples, 12 type samples, 18 file samples, and 72 byte-range requests.
All metadata responses, including error bodies, retain the 4 MiB ceiling.
`--allow-disposable-write` additionally enables synthetic display-preference round trips.
Each process owns one fresh namespace. It cannot write to a caller-selected item/client scope.
The write mode preserves defaults, retries identical values, and removes synthetic keys afterward.
Preference scope rows remain. The probe never calls playback-reporting or metadata-update endpoints and never supplies another real user's ID.
Standard item GETs can perform Jellyfin's on-demand refresh; downloads can add download-activity entries.
Review the report before enabling writes.

`probe_test.dart` uses a synthetic loopback HTTP server to test the probe's safety and filtering.
`whole_set_fixture.dart` demonstrates full-set replacement counterexamples with synthetic file-backed state.
Its schedules serialize stale writes deliberately. They are not concurrent Jellyfin requests.
File reopening is not a Jellyfin restart or a process-restart test.

`public-evidence.json` is a captured public-only run.
`local-evidence.json` is captured model output.
`authenticated-evidence.json` contains sanitized live administrator counts and range outcomes.
`extension-evidence.json` records public deployment/source comparisons, not live storage-write tests.
It contains no personal titles, source paths, item/account identifiers, credentials, tokens, or media bytes.
These files are not compatibility guarantees. Only the last file records authenticated live results.
