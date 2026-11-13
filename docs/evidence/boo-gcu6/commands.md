# boo-gcu6 verification record

Original review base: `eb64fe705198fba0563df0a188939f6e57e16f35`.
Worktree: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-c6dae15e`.
Initial recorded branch: `t3/c6dae15e`.
Final branch: `t3/persist-settings-on-change`.
The lead did not issue a checkout switch or branch rename.

All commands below run from this worktree. Flutter tests use concurrency two.
Commands ran sequentially. No command was interrupted. The developer shell
prints missing iPhone SDK warnings; these runs do not exercise iOS or Android
latency. SQLite counts measure executed work, not elapsed-time performance.

## Initial failure and iteration

| Command | Result | Log |
| --- | --- | --- |
| `nix develop --command flutter test --concurrency=2 test/playback/domain_settings_test.dart` | Exit 1: four expected behavior/work failures against original implementation; repeated once with bounded failure printing. The saved log is the second run; the first verbose log was overwritten. | `red.log` |
| `nix develop --command dart format lib/playback/store.dart lib/playback/database.dart test/playback/domain_settings_test.dart` | Exit 0. | `format-iteration.log` |
| `nix develop --command flutter test --concurrency=2 test/playback/domain_settings_test.dart` | Exit 0: 4 passed. | `green-iteration-1.log` |
| `nix develop --command flutter test --concurrency=2 test/playback/domain_settings_test.dart --plain-name 'reader record saves never copy or encode unchanged PDF choices'` | Exit 1: test setup lacked a reading position; no bookmark was created. This was not meaningful red. | `reader-red.log` |
| `nix develop --command flutter test --concurrency=2 test/playback/domain_settings_test.dart --plain-name 'reader record saves never copy or encode unchanged PDF choices'` | Exit 1: test imported the wrong file for PdfAddress. This was not meaningful red. | `reader-red-2.log` |
| `nix develop --command flutter test --concurrency=2 test/playback/domain_settings_test.dart --plain-name 'reader record saves never copy or encode unchanged PDF choices'` | Exit 1: meaningful red with original reader caller: one unnecessary worker settings copy, expected zero. | `reader-red-3.log` |
| `nix develop --command flutter test --concurrency=2 test/playback/domain_settings_test.dart test/playback/settings_worker_test.dart test/reader/reading_changes_test.dart test/reader/pdf_preferences_store_test.dart` | Exit 1: 27 passed, 1 browser assertion failed because the test adaptation looked for native settings in the browser's combined format. Corrected the assertion; browser format is unchanged. | `focused-1.log` |
| `nix develop --command dart format lib/playback/store.dart lib/playback/database.dart lib/reader/session.dart test/playback/domain_settings_test.dart test/playback/settings_worker_test.dart test/reader/reading_changes_test.dart test/reader/session_native_test.dart` | Exit 0. | `format-iteration-2.log` |

The listening-position reproduction wrote combined settings three times and
encoded them in a worker three times after 2,000 nested PDF book choices
existed. One batch acknowledgment wrote and encoded them once. Initial green
counts: zero writes and zero worker text encodes for both operations; a
listening-settings change writes only `listening`, and a reading-settings
change writes only `reading`. Real SQLite triggers count assignments even
when assigned text equals existing text. Worker instrumentation runs the real
function in a real isolate and records its returned text or settings copy.

## Scope and callers

ResumeStore owns in-memory records and the durability baseline. RecordDatabase
owns SQLite commits, now with one settings row per account and domain.
The existing transaction writes domain settings and journal changes together.
No journal, pending-action inventory, or writer abstraction was added.

Playback supplies a bounded scalar settings map on saves. The store compares
it without inspecting the reading map. ReaderSession replaces its per-book
PDF map on edits. It can therefore detect unchanged submitted settings with
five top-level comparisons, without walking per-book entries. ReadingChanges
can omit settings while retaining record changes and failed settings retries.
Whole snapshot writers, migration, explicit recovery, and browser whole-account
storage keep their existing semantics. Browser preferences still encode and
replace the whole account and do not promise native per-domain writes.

## Broader tests and audit fixes

| Command | Result | Log |
| --- | --- | --- |
| `nix develop --command flutter test --concurrency=2 test/sync test/playback test/durability test/app test/reader test/settings` | Exit 1: 2,597 passed, 24 skipped, 2 failed. Both version-three upgrade tests used a helper that retained the new settings table while relabeling a new database as version three. Fixed that helper to reconstruct combined settings and remove the new tables. | `affected-1.log` |
| `nix develop --command flutter test --concurrency=2 test/playback/domain_settings_test.dart test/reader/reading_changes_test.dart` | Exit 1: 13 passed, 3 expected regressions. The first reading save after restore still copied settings; a page turn still sent unchanged settings; applying a settings replacement retained an omitted legacy preference. | `restore-red.log` |
| `nix develop --command dart format lib/playback/store.dart lib/playback/database.dart lib/reader/session.dart test/playback/domain_settings_test.dart test/reader/reading_changes_test.dart test/research/current_restore_measurement_test.dart` | Exit 0. | `format-iteration-3.log` |
| `nix develop --command flutter test --concurrency=2 test/playback/domain_settings_test.dart test/playback/settings_worker_test.dart test/reader/reading_changes_test.dart test/reader/pdf_preferences_store_test.dart test/sync/restore_current_test.dart` | Exit 0: 51 passed. Includes both corrected version-three upgrade tests. | `focused-2.log` |

The reader now starts its submitted-settings baseline from restored preferences.
A settings-free ReadingChanges keeps the existing preferences; an explicit
settings map remains a replacement, preserving the old caller contract.
Pending changes merge omitted settings with an earlier unsaved settings change.
The durability baseline inside ResumeStore still advances only after commit.

Logs are kept locally as `.log` files and committed as byte-for-byte `.log.gz`
copies. Decompress a committed copy with `gzip -dc <file.log.gz>`. The local
text files are ignored by the repository's existing `*.log` rule.

| Command | Result | Log |
| --- | --- | --- |
| `nix develop --command flutter test --concurrency=2 test/sync test/playback test/durability test/app test/reader test/settings` | Exit 1: 2,598 passed, 24 skipped, 3 failed. Existing EPUB saved-place tests for showcase-frost, showcase-salt, and showcase-winter caught loss of the one-time legacy `sizesMainText` preference migration. | `affected-2.log` |
| `nix develop --command flutter test --concurrency=2 test/playback/domain_settings_test.dart --plain-name 'legacy text sizing migrates once without resending settings on later reading saves'` | Exit 1: reproduced the missing migration with real SQLite: expected one reading-domain write, observed zero. | `migration-red.log` |

The correction retains raw saved font size and the saved `sizesMainText` flag
in the reader's submitted-settings baseline. A derived legacy flag or clamped
font size therefore remains a real pending preference change. Validated PDF
choices share their existing map identity, so an unchanged map is not scanned.

| Command | Result | Log |
| --- | --- | --- |
| `nix develop --command flutter test --concurrency=2 test/playback/domain_settings_test.dart test/reader/session_native_test.dart test/reader/reading_changes_test.dart` | Exit 0: 46 passed, including all three previously failing EPUB migration cases. | `migration-green.log` |
| `nix develop --command dart format lib/playback/store.dart lib/playback/database.dart lib/reader/session.dart test/playback/domain_settings_test.dart test/playback/settings_worker_test.dart test/reader/reading_changes_test.dart test/reader/session_native_test.dart test/research/current_restore_measurement_test.dart` | Exit 0. | `format-final.log` |

The final full-suite command reruns every required affected suite after the
migration correction, as well as the rest of the Flutter project. The saved
failed affected-suite runs remain evidence of the regressions found and fixed;
they are not presented as passes.

## Final migration audit and static checks

| Command | Result | Log |
| --- | --- | --- |
| `nix develop --command flutter test --concurrency=2` | Exit 0: 3,530 passed, 27 skipped. This run preceded the retained-original count correction described below. | `full.log` |
| `nix develop --command flutter test --concurrency=2 test/playback/domain_settings_test.dart --plain-name 'schema five settings migrate atomically and retry without changing journal state'` | Exit 1: meaningful failure after adding a retained wire original and a discovery cursor to the schema-five fixture. ResumeStore's cached original count disagreed with the durable database after migration. | `originals-red.log` |
| `nix develop --command flutter test --concurrency=2 test/playback/domain_settings_test.dart test/sync/restore_current_test.dart test/sync/unreadable_discovery_test.dart test/sync/repair_recovery_test.dart test/durability/record_store_test.dart` | Exit 0: 133 passed. | `originals-green.log` |
| `nix develop --command dart format lib/playback/store.dart test/playback/domain_settings_test.dart` | Exit 0. | `format-originals.log` |
| `nix develop --command flutter analyze lib/playback/store.dart lib/playback/database.dart lib/reader/session.dart test/playback/domain_settings_test.dart test/playback/settings_worker_test.dart test/reader/reading_changes_test.dart test/reader/session_native_test.dart test/research/current_restore_measurement_test.dart` | Exit 1: two avoid_print lint findings in test work-count diagnostics. Changed those diagnostics to stdout.writeln. | `analyze.log` |
| `nix develop --command flutter analyze lib/playback/store.dart lib/playback/database.dart lib/reader/session.dart test/playback/domain_settings_test.dart test/playback/settings_worker_test.dart test/reader/reading_changes_test.dart test/reader/session_native_test.dart test/research/current_restore_measurement_test.dart` | Exit 0: no issues. | `analyze-final.log` |
| `nix develop --command dart format --output=none --set-exit-if-changed lib/playback/store.dart lib/playback/database.dart lib/reader/session.dart test/playback/domain_settings_test.dart test/playback/settings_worker_test.dart test/reader/reading_changes_test.dart test/reader/session_native_test.dart test/research/current_restore_measurement_test.dart` | Exit 1: one long test diagnostic required wrapping after the logging change. This command wrote no files. | `format-check.log` |

The migration now passes its restored count of existing wire originals into
the normal persistence operation. Both commit success and file reconstruction
use that same count. Imported preference originals still use their staged
rows, and normal cached updates keep their existing count. The schema-five
test retains the exact original body, cursor 31, pending record, and settings
through failed migration, retry, invariant checks, and the next position save.

## Completed checks before review

| Command | Result | Log |
| --- | --- | --- |
| `nix develop --command flutter test --concurrency=2` | Exit 0: 3,530 passed, 27 skipped on the final behavior revision, including every required sync/playback/durability/app/reader/settings suite. | `full-final.log` |
| `nix develop --command dart format test/playback/domain_settings_test.dart` | Exit 0: wrapped the diagnostic line; no behavior change. | `format-diagnostic.log` |
| `nix develop --command dart format --output=none --set-exit-if-changed lib/playback/store.dart lib/playback/database.dart lib/reader/session.dart test/playback/domain_settings_test.dart test/playback/settings_worker_test.dart test/reader/reading_changes_test.dart test/reader/session_native_test.dart test/research/current_restore_measurement_test.dart` | Exit 0: 8 files, 0 changes. | `format-check-final.log` |
| `nix develop --command git diff --check` | Exit 0. | `diff-check.log` |

The 27 skips are the suite's explicitly gated integration/research/corpus
checks; their reasons remain in the full logs. No device, coverage, mutation,
deployment, push, PR, merge, or closure command ran. No timing threshold was
substituted for work counts. This evidence makes no Android latency claim.

The settings table and its set-aside counterpart are the only new durable
storage. Listening and reading snapshots keep their old shape. The journal
remains the sole record and pending-action authority. The new original-count
argument is restoration bookkeeping inside ResumeStore, not a second inventory.

`nix develop --command git diff --cached --check` also exited 0 after staging
all named files, including the new test. Log: `staged-diff-check.log`.

## Completed independent review

The sole authorized reviewer inspected the complete original-base-to-head
range ending at `9af2b94356c9cb9f7ce59d3bff532294d9d8b340`, the real callers,
and the saved verification evidence. The reviewer used Codex `gpt-6-astra`
with high reasoning effort, shared isolation, and asynchronous read-only
review. The reviewer ran no builds or tests and made no edits.

Original verdicts are preserved without revision in `review.json`:
correctness pass, ticket fulfillment pass, and software design pass, with
no findings. The reviewer verified all 29 pre-review compressed log hashes
and their equality with the local text logs. Review gaps are preserved in
that JSON. The branch documentation gap is resolved above and in the ticket.
No material acceptance requirement remains unverified within the authorized
host-test scope.

The final evidence commit changes documentation only. No behavior changed
after review, so the completed full suite and analysis remain applicable.
Final evidence diff checks are recorded below; no test run was repeated.

| Command | Result | Log |
| --- | --- | --- |
| `nix develop --command git diff --check` | Exit 0. | `review-diff-check.log.gz` |
| `nix develop --command git diff --cached --check` | Exit 0. | `review-staged-diff-check.log.gz` |

All owned commands and the sole reviewer have finished. There are no product
forks or review findings to resolve. The ticket remains in progress for the
parent's integration, acceptance, hardening, and closure.
