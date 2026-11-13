# td-bz4y evidence

The four named research owners now set the modification time of the ZIP entries
they create. The Dart replacement leaves all decoded source entries alone. The
Python owners use explicit `ZipInfo` timestamps. Fixture interfaces, entry order,
payloads, compression and test assertions remain unchanged. The correction is
limited to archive construction; it makes no product or server-behavior claim.

## Controlled proof

Both diagnostics run real encoders at local January 1, 2026, 12:00:00 and
12:00:02. They compare complete archive byte arrays, with independent builds.
No sleeps, clock-boundary waits, timing-limit changes or larger fixtures occur.

| Diagnostic | Valid red | Green | Content sensitivity |
| --- | --- | --- | --- |
| Python's three owners | 04: 3 failures, 4 passes | 06: 7 passes | Each writer changes its output when one existing payload changes |
| Dart cover replacement | 09: 1 failure, 2 passes | 10: 3 passes | Changing the input OPF title changes the result |

Every green run also passes an unfixed-writer control: its bytes still change
between the two times. The output is therefore stable because of the owner
correction, not because the diagnostic froze or bypassed the encoder.

`preservation-observations.json` compares all 12 Python observations and all four
Dart observations across valid red and green. Ordered names, payload hashes,
compression and attributes are equal. Every decoded original Dart entry also
keeps its modification time. `preserved.json` checks unchanged source paths,
including root Flutter code/tests, locks, checked-in fixtures and security probes.

The calibration archive is an existing one-chapter partial fixture, not a complete
publication. It remains that way. No claim is made that its mocked OCR (text
recognition from images) proves any model or device behavior.

## Reproduction and package checks

Run from the worktree root. Every recorded command ran within the root pinned
`nix develop` shell. `commands.jsonl` records the exact child command, working
directory, exit status, dates and hashes of complete compressed output and the
research source diff. For example:

```sh
nix develop --command python3 docs/evidence/td-bz4y/run.py <name> <command> <arguments>
```

The initial package preparation is command 05, which enters the separate pinned
readers shell through `nix develop ./tool/research/readers`. It unpacks the pinned
epubx dependency with the existing compatibility patch and converts the three
checked-in MOBIs into ignored `_out` prerequisites. It does not regenerate the
checked-in fixtures or acquire/regenerate the optional public corpus. Dependency
resolution uses `--enforce-lockfile`. The converter itself is outside this ticket.

`diagnostic/python_times.py <observations.json>` invokes the actual test method,
test setup or `seed_media`, as applicable. It temporarily removes Nix's
`SOURCE_DATE_EPOCH` and controls Python's ZIP default clock. For changed-content
checks it replaces one text payload at the real encoder's input. The sync check
uses a temporary root with existing dummy audio paths and a stubbed ffprobe
chapter result, so the real EPUB writer runs without ffmpeg, network or servers.
It rejects any unexpected audio command.

`diagnostic/dart_probe.py <unique-stage-name>` copies archive 4.6.0 to a private
ignored directory. Its only dependency change permits a Dart Zone (a scoped
execution context) to supply the lazy default modification time. The existing
inline cover archive construction is moved temporarily to a diagnostic function;
the original test is routed through that same function. There is no second
builder implementation. The diagnostic calls that function with each time and
uses the real source conversion for its content-change check. The pinned test
runner is invoked directly with an explicit package configuration to retain the
private dependency root. The script restores source, configuration and the
temporary input edit; restoration files record byte equality and hashes.
Compressed before/instrumented source and the dependency patch are retained.

To reproduce red, use the four owners from the original base in a separately
authorized checkout; to reproduce green, use this commit. The diagnostic scripts
are evidence, not a new permanent test framework or public clock interface.
Choose a fresh stage name because private copies deliberately are not overwritten.

Commands 12–18 ran sequentially through `nix develop --command bash
docs/evidence/td-bz4y/verify.sh`. Its `set -e` stopped at the pre-existing package
analysis warning; command 19 ran the remaining format check separately. Command
20 then analyzed the changed Dart file successfully. `verify.sh` documents this
original sequence, including the analysis result; it is not a claim that all
steps exit zero on an unchanged base.

| Package | Focused result | Complete applicable result |
| --- | --- | --- |
| epub_engines | 9 passed | 102 passed, no skips |
| sync | 8 passed, 4 server tests skipped | 27 passed, 13 server tests skipped |
| dart_compat | 5 passed | 5 passed, 4 existing corpus tests skipped |

`results.json` and complete logs give the test names and skip reasons. The sync
runner discovers the full package suite and explicitly skips the 13 tests that
start local HTTP servers. This conservatively follows the ticket's prohibition
on server actions; it changes no checked-in test source or original assertion.
The other sync tests and the real EPUB writer diagnostic run. Live Jellyfin
experiments, restart/upgrade checks, device workloads and actual OCR calibration
are excluded. The four corpus tests retain their existing `BOOKFIN_REAL_CORPUS`
gate. No missing corpus or models are fetched.

The complete Dart package analysis reports the existing `unnecessary_cast` in
unchanged `test/corpus_test.dart:45:18` and exits 2. Follow-up ticket `t0-bbyo`
records it. Analysis of the changed file and its format check pass. No root
Flutter suite, coverage, mutation campaign or device/browser action was run.

## Failures and limits

`failures.json` separates meaningful red evidence, diagnostic setup failures,
the corrected summary-script syntax error, exploratory path errors, the existing
analysis warning, and non-fatal platform-tool notices. No failed command is
counted as successful verification. The initial Python and Dart diagnostic runs
failed their controls and are explicitly not meaningful red evidence.

Stability is established for the same source payloads and pinned encoder on this
host, under distinct encoding times. Cross-version, cross-time-zone and native
MOBI converter determinism are not claimed. No historical reader failure is
attributed to these research fixtures: their current callers use payloads or
metadata rather than rebuilt publication identities.

Parent integration, acceptance, hardening and ticket closure remain separate.
`HASHES.sha256` covers all evidence files except itself and is refreshed after
each archived command. The single review and any finding resolutions are added
after the implementation commit.
