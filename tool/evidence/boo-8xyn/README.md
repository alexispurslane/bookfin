# boo-8xyn: catalog worker facts

## Scope and starting state

Worktree: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-b2f263a5`.
Branch: `t3/catalog-worker-facts`.
Original base and initial HEAD: `6a5e2b95fa449be40c8de74431718346fb85b180`.
The initial working tree was clean. The ticket was already in progress;
`tk start boo-8xyn` retained that status. `tk ready` and the dependency tree
showed boo-7z9a closed, with boo-jlhy also closed. No checkout was created,
reset, switched or removed. No merge, push, PR, deployment or ticket closure.

The parent caller audit is authoritative. This is a representation change in
CatalogController, with no new owner, worker service, file format or cache.
Concurrent text/outline and playback/sync production files are untouched.

## Caller and retention audit

All reads below were inspected before production edits. A repository-wide
search covered lib, test, integration_test and tool Dart files.

| Caller or retained value | Requirement and final representation |
| --- | --- |
| `_restoreCatalog`, `_refreshCatalog`, `_reviseCatalog`, `_saveCatalog` | Return facts, text and derived library through `_Built`; no CatalogCache in a result. Unchanged refresh may return null or a null library as before. |
| `_adopt` | Remains the one adoption path for catalog facts, text, known stored state, saved access and the prepared library. Account/request ownership guards remain. |
| `_adoptChoices`, `_selectLibraries`, `_edit` | Send account scope, retained text and choices. Existing workers decode the text, then derive books or compare visibility. No server digest, encode or write for a choice change. |
| `_readSaved`, `_restore`, `_signIn` | Keep cache-first loading and separate choice loading. Restore obtains saved library names from facts. |
| `resume`, `setHiddenLibraries`, `_refresh`, `_saveAccess` | Use saved completion time, complete-library ids, content digest and saved access from facts; preserve metadata comparison and write uncertainty. |
| `checkInvariants` | Temporarily decodes retained text, checks all retained facts, included libraries, source ownership and choice-derived books. Never retains that decode. |
| `LibraryShelf` in library_view.dart | Uses `!hasCatalog` for the first-refresh message. Empty loaded catalogs remain different from absent catalogs. |
| Settings reset-corrections row | Uses `hasCatalog` and the existing account access flag. Keeps its existing narrow subscriptions. |
| catalog_signals_test.dart | The failed-denial test checks the saved text's access flag, preserving the distinction between current denied access and the unchanged saved allowed catalog. |
| choices_test.dart | The interrupted-choice-read denial test uses `hasCatalog`; it still checks invariants and restart behavior. |

The retained `_CatalogFacts` record holds only AccountScope, BookLibrary names
and ids, included-library ids, completion time, saved access and content digest.
AccountScope contains URI/string identity; BookLibrary contains two strings.
The lists and sets come from the existing immutable CatalogCache metadata.
They have no back-reference to that cache or to entries.

The controller has no CatalogCache field, and its normal instance methods have
no CatalogEntry input. Its only decoded-cache local is inside checkInvariants;
the separate first-denial path builds an empty disposable cache as before.
The source audit of model.dart and shelf.dart confirms that Book, Edition,
SourceFile, AudioChapter, CoverRef and CatalogLibrary keep derived values and
indexes, not CatalogEntry or raw server maps. `_SourceEdition` references
CatalogEntry only during buildBooks; it is not part of the resulting library.
No entry graph is captured by the top-level production worker callbacks.

The latest reported library names and saved library names remain distinct:
Jellyfin can report new names before a catalog fetch/save completes. This
existing distinction is required for failed-refresh and account behavior.

## Boundary proof and transfer semantics

Tests use the existing IsolateHop injection and real Isolate.run workers.
They inspect actual worker inputs/results, record worker book-build counts,
and assert usable books, unchanged stored text and no network for known
visibility changes. The existing test helper detects CatalogEntry/CatalogCache
in record representations; it is a targeted boundary probe, not a general
heap walker. Static field/caller inspection above establishes that facts and
derived books contain no hidden path to entries. No production diagnostics
were added.

Five red failures occurred against unchanged production code: restored and
refreshed catalogs and saved denials returned entries, while corrections and
visibility changes supplied entries to workers. Three existing boundary
behaviors passed. After implementation all eight passed. Correction and
visibility inputs now contain the exact retained text object, and their
storage text remains identical. Restore/refresh/denial results carry no entry
container. Existing tests separately prove one worker book build per changed
catalog and zero UI book builds, except the measured small empty case.

`00-transfer.txt` records source inspection through the Nix dev shell:

- Flutter 3.47.4 native `_isolates_io.dart` calls Isolate.run with callback and
  message; `_isolates_web.dart` calls the callback on the current event loop.
- Dart 3.13.3 `lib/isolate/isolate.dart` documents immutable strings as shared,
  mutable message graphs as copied, and Isolate.run results as delivered by
  Isolate.exit without copying. Closures can capture excess state; production
  callbacks here are top-level functions.
- The change removes the returned/retained decoded entry graph and replaces
  decoded-entry inputs with text. It does not claim an avoided result-copy
  cost, measured heap bytes, garbage-collection timing, Android launch speed,
  or browser off-thread execution. The survey's 20–30 MB figure is unmeasured.
- The existing 512-character and one-entry thresholds are unchanged. Empty
  choice rebuilds now use the same text-size rule as restore/access revision;
  a large empty snapshot's decode cannot run inline just because it has no books.

## Commands and results

All commands run in the worktree. Every Flutter command uses Nix and test
concurrency two. One heavy command runs at a time. Captures retain failures
and skips. Trailing horizontal whitespace in saved output is removed before
commit so the complete base-to-head diff is whitespace-clean.

| Log | Exact command | Outcome |
| --- | --- | --- |
| 01-boundary-red.txt | `nix develop --command flutter test --concurrency=2 test/catalog/catalog_signals_test.dart --name 'what crosses to the worker' --reporter expanded` | Exit 1: five expected boundary failures, three passed. No missing symbols or syntax failures. |
| 02-format.txt | `nix develop --command dart format lib/catalog/controller.dart lib/catalog/library_view.dart lib/settings/screen.dart test/catalog/catalog_signals_test.dart test/catalog/choices_test.dart` | Exit 0: five files, two formatted. |
| 03-boundary-green.txt | Same command as 01-boundary-red.txt | Exit 0: eight passed. |
| 04-signals-choices.txt | `nix develop --command flutter test --concurrency=2 test/catalog/catalog_signals_test.dart test/catalog/choices_test.dart --reporter expanded` | Exit 0: 109 passed. |
| 05-affected.txt | `nix develop --command flutter test --concurrency=2 test/catalog test/settings test/app test/downloads test/playback test/sync --reporter expanded` | Exit 0: 1,563 passed, three opt-in integration skips. |
| 06-full.txt | `nix develop --command flutter test --concurrency=2 --reporter expanded` | Exit 0: 3,554 passed, 27 skips; no failures. |
| 07-format-check.txt | `nix develop --command dart format --output=none --set-exit-if-changed lib/catalog/controller.dart lib/catalog/library_view.dart lib/settings/screen.dart test/catalog/catalog_signals_test.dart test/catalog/choices_test.dart` | Exit 0: five files, zero changes. |
| 08-analysis.txt | `nix develop --command flutter analyze --no-pub lib/catalog lib/settings test/catalog test/settings test/app test/downloads test/playback test/sync` | Exit 0: no issues. |

The small rename after 04 changes local variable names from cache to facts;
subsequent affected/full checks cover it. No behavior or threshold changed.

The affected-suite skips are plugin_upgrade_integration_test.dart,
plugin_batch_integration_test.dart and plugin_integration_test.dart. They
require their explicit pinned-shell proof runners. No failure occurred in 05.

The full-suite skips are the opt-in benchmarks and research measurements,
missing optional ebook corpus/trial books and three live-plugin checks. Exact
reported reasons and the three boolean-skip source guards are in `skips.txt`.
The speech tests deliberately exercise stuck-worker shutdown; their diagnostic
messages in 06 are not additional skipped tests. Both known intermittent tests
passed in the affected/full runs; their causes remain unresolved.

All owned build/test/format/analysis commands completed. No process was killed.
The source-audit command for 00 is recorded in `commands.txt`.

## Limits

Device/browser checks, coverage and mutations were excluded by the task.
Android Device panel issue t1-dth0 and browser PDF dart:ffi blocker t7-3j9c
were not retried. Known intermittent failures t5-rplx and tf-il7u remain
unexplained; a passing run is not a cause finding. iOS SDK warnings emitted by
Flutter do not establish iOS support. No device performance measurement was
attempted. Integration, acceptance, hardening and closure belong to the parent.
