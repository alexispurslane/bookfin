# Section CSS evidence

Original review base: `eb64fe705198fba0563df0a188939f6e57e16f35`.
Worktree: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-fbb08cd5`.
Branch: `t3/section-css-dependencies`.

## Ownership and caller audit

`Publication.bookStyles` remains the authoritative original CSS text.
Admission derives a private list of external CSS paths for each spine section.
The lists include imports regardless of media conditions. The admitted record
stores paths, not another copy of the CSS text. Revision 6 rebuilds revision 5
records through the existing admitted-book path.

`Publication.stylesForSection` creates a detached map from those paths. Each
preparation worker receives that map. No worker captures the publication.
The tests place an unsendable Finalizer on the observed publication to detect
such a capture, and report each map's keys from inside the actual isolate.

| Caller | Input after this change |
| --- | --- |
| `PageSource._prepare` → `_prepareInWorker` | One section's CSS map |
| `PageSource.findPlace` → `_partInWorker` | One section's CSS map, also for whole fallback |
| `PageSource.shownMainText` → `_measureInWorker` | One CSS map for each of the three selected sections |
| `_Admission._sectionFaces` and `_mainTextSize` | The authoritative CSS map within the existing admission isolate; no transfer |
| `tool/reader` and `test/reader/epub/corpus` direct preparation probes | Existing full-map inputs, retained as independent comparison inputs |

Both dependency collection and rendering use `_sectionCss` for document-order
links and inline sheets. Both use `_SheetParser` for import syntax and paths.
Dependency collection stops before selectors and declarations. It follows all
conditional imports and tracks the shortest import depth per path. A deep
conditional route cannot suppress a shorter route that is active under other
settings. Rendering retains its original media decisions, read-once order,
cycles and depth limit.

Decode checks that each distinct spine path has one dependency list. Every
listed resource must exist in `bookStyles`, and lists must be sorted and unique.
Malformed records follow the existing `.unreadable` preservation and admission
path. The on-demand invariant checker additionally derives and compares the
dependencies. Reopening does not reparse every section to check semantic equality.

ChapterTitles, paragraph measurement ownership, excerpt ownership, font
selection, and image-size inputs retain their existing implementation.
The two test publication wrappers forward the new query.

## Transfer estimate audit

The pinned Dart SDK is 3.13.3. Its `SendPort.send` documentation says:
“Objects that are identified as immutable (e.g. strings) will be shared whereas
all other objects will be copied.” It also describes a linear cost for copying
the transitive object graph. The `Isolate.run` documentation states that its
result uses `Isolate.exit` and arrives without copying. See `dart-transfer.txt`.

Source: the SDK's `lib/isolate/isolate.dart`, lines 197–208 and 1009–1027.
Public API references: <https://api.dart.dev/dart-isolate/SendPort/send.html>
and <https://api.dart.dev/dart-isolate/Isolate/run.html>.

The survey's 300 × 300 KB = 90 MB arithmetic does not establish copied CSS string
bytes. Strings are shared. This change reduces map entries and unrelated
resources reachable from worker inputs. It does not cache parsed CSS or remove
the existing repeated parsing of linked sheets. Those sheets were already the
only sheets the style parser read. No latency or Android improvement is claimed.

Controlled inputs contain 48 CSS resources, of which section zero needs five.

| Operation | Previous worker map entries | Selected worker map entries |
| --- | ---: | ---: |
| Whole section | 48 | 5 |
| Partial section plus its whole replacement | 96 across two workers | 10 across two workers |
| Three-section main-text sample | 48 in one shared map | 7 across three maps in one worker |

`05-paths-real-book.txt` incorrectly counted the old shared sample map three
times (144). The test report was corrected before `06-focused.txt`. The table
above and subsequent logs use the actual worker input count, 48.

The committed Project Gutenberg Alice MOBI fixture converts through the real
importer. Its 19 sections are compared at narrow/day and wide/night settings,
both after conversion and after reopening its admitted record with the original
file unavailable. These 38 section inputs use 74 map entries instead of 114.
Every prepared output dump matches the full-map input. The fixture's source and
rights are in `tool/research/readers/fixtures/README.md`.

## Commands and outcomes

All commands below run from the worktree. Every Flutter test command uses
`--concurrency=2`. Only one build, test or analysis command runs at a time.
At the red checkpoint the new query was a behavior-preserving alias for the
full `bookStyles` map. PageSource still passed `bookStyles` to all three workers.

| Log | Exact command | Result |
| --- | --- | --- |
| `01-red.txt` | `nix develop --command flutter test --concurrency=2 test/reader/epub/section_styles_test.dart --reporter expanded` | Exit 1: three expected full-map failures; partial fixture did not reach the 256 KiB path and failed its path assertion. Corrected before the next run. Two comparisons passed. |
| `02-red.txt` | `nix develop --command flutter test --concurrency=2 test/reader/epub/section_styles_test.dart test/reader/admitted_books_test.dart --name 'CSS\|conditional short routes' --reporter expanded` | Exit 1: 12 meaningful failures, one pass. All three real worker paths carried irrelevant CSS. Revision and damaged-record cases also failed as expected. |
| `03-green.txt` | Same command as `02-red.txt` | Exit 0: 13 passed. |
| `04-format.txt` | `nix develop --command bash -c 'dart format lib/reader/epub/css.dart lib/reader/epub/prepare.dart lib/reader/epub/publication.dart lib/reader/epub/page_source.dart test/reader/epub/section_styles_test.dart test/reader/epub/page_source_test.dart test/reader/admitted_books_test.dart'` | Exit 0. |
| `05-paths-real-book.txt` | Same command as `01-red.txt` | Exit 0: eight passed, including real Alice conversion/reopen comparisons. Sample report corrected as stated above. |
| `06-focused.txt` | `nix develop --command flutter test --concurrency=2 test/reader/publication_test.dart test/reader/admitted_books_test.dart test/reader/mobi_document_test.dart test/reader/epub --reporter expanded` | Exit 1: 731 passed, 20 skipped, three chapter-title tests failed because their publication wrapper lacked `stylesForSection`. |
| `07-chapter-titles-fix.txt` | `nix develop --command flutter test --concurrency=2 test/reader/epub/chapter_titles_test.dart --reporter expanded` | Exit 0: eight passed after forwarding the new query in the wrapper. Original chapter behavior assertions remain intact. |
| `08-reader-crossings.txt` | `nix develop --command flutter test --concurrency=2 test/reader test/crossings --reporter expanded` | Exit 0: 1,706 passed, 21 opt-in tests skipped. Includes all publication, admitted-book, MOBI and EPUB focused suites again. |
| `09-format.txt` | `nix develop --command dart format lib/reader/epub/css.dart lib/reader/epub/prepare.dart lib/reader/epub/publication.dart lib/reader/epub/page_source.dart test/reader/epub/section_styles_test.dart test/reader/epub/page_source_test.dart test/reader/epub/chapter_titles_test.dart test/reader/admitted_books_test.dart` | Exit 0: eight files formatted, one changed. |
| `10-analyze.txt` | `nix develop --command flutter analyze --no-pub lib/reader/epub/css.dart lib/reader/epub/prepare.dart lib/reader/epub/publication.dart lib/reader/epub/page_source.dart test/reader/epub/section_styles_test.dart test/reader/epub/page_source_test.dart test/reader/epub/chapter_titles_test.dart test/reader/admitted_books_test.dart` | Exit 1: two `avoid_print` diagnostics in test evidence output. Replaced those calls with `debugPrint`. |
| `11-analyze.txt` | Same command as `10-analyze.txt` | Exit 0: no issues. |
| `12-full.txt` | `nix develop --command flutter test --concurrency=2 --reporter expanded` | Exit 1: 3,534 passed, 27 skipped, one failure in the unchanged scheduled-frame test. |
| `13-frames-repeat.txt` | `nix develop --command flutter test --concurrency=2 test/reader/epub/page_source_frames_test.dart --reporter expanded` | Exit 0: all five unchanged frame tests passed. |
| `14-full-repeat.txt` | `nix develop --command flutter test --concurrency=2 --reporter expanded` | Exit 0: 3,535 passed, 27 skipped. No frame-test or scheduler changes. |
| `15-format-check.txt` | `nix develop --command dart format --output=none --set-exit-if-changed lib/reader/epub/css.dart lib/reader/epub/prepare.dart lib/reader/epub/publication.dart lib/reader/epub/page_source.dart test/reader/epub/section_styles_test.dart test/reader/epub/page_source_test.dart test/reader/epub/chapter_titles_test.dart test/reader/admitted_books_test.dart` | Exit 0: eight files, zero changes. |
| `16-diff-check.txt` | `git diff --check` | Exit 0, no output. |

The three failures in `06-focused.txt` were:

- `repeated page reports use section facts prepared in the worker`.
- `worker-prepared parts and their whole replacement report the same chapter`.
- `section titles survive eviction, settings changes and reopening`.

The failure in `12-full.txt` was
`page_source_frames_test.dart: idle layout gives way to each frame that is
scheduled, and goes on once no frame is scheduled`. At line 188, `far()` was
true instead of false (`idle steps ran in a row between frames`). The preceding
reader/crossings run passed this test. The frame test and scheduling code did
not change. Its fixture has only one CSS sheet, so selection still supplies the
same sheet. Cause is not established. Follow-up ticket `tf-il7u` records the
failure and the possible startup scheduling race without treating that cause as
proven. No delay, threshold or assertion was changed.
The targeted rerun passed all five frame tests. The second full run passed all
3,535 tests, with 27 opt-in/platform skips. The intermittent failure remains a
follow-up rather than a claimed fix.

Nix/Flutter prints unavailable `iphoneos` and `iphonesimulator` SDK warnings on
this host. Host Flutter tests still execute. No iOS or Android result is claimed.
No owned command was interrupted. Read-only exploratory searches also reported
absent optional corpus-cache paths, a nonexistent `test/reader/mobi_test.dart`
(the real suite is `mobi_document_test.dart`), and some no-match exits. One patch
failed its context match without changing files, then succeeded with narrower
context. None was treated as successful verification.
