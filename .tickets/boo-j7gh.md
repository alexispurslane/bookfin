---
id: boo-j7gh
status: in_progress
deps: []
links: []
created: 2026-11-12T23:41:02Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---

## Launch — 2026-11-13

Astra xhigh lead launched from a85c8789e9a14c4d978f94e64db3c6cacfafd8a0.
Running, stage uncertain; branch not yet reported. Exactly one fresh read-only
Astra high reviewer authorized. Parent closes after integration and verification.

- clientRequestId: bookfin-boo-j7gh-astra-20261113-1
- taskId: node:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-boo-j7gh-astra-20261113-1
- childThreadId: thread:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-boo-j7gh-astra-20261113-1
- Link: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-boo-j7gh-astra-20261113-1>

# Count visible book characters with one walker and measure the outline once

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/speech/book_words.dart:94-164 and lib/reader/book_map.dart:528-531 each walk a section and count visible characters, and the two counts must agree to the character. Only one fixture test compares them. A change to what counts as visible in one walker moves every speech landing silently. `BookWords` also calls `measureTextOutline` again, though Crossings already holds that outline. Use one walker that yields each text run with its visible offset, and pass the kept outline into the read job.

## Parent caller audit and settled scope — 2026-11-13

At `950ad803`, `countSection` and `bookWordsOf` parse body events independently.
Both count non-whitespace UTF-16 code units; `isWhiteSpace` already matches
Dart's whitespace expression. Speech tokenization additionally joins inline
markup, separates block boundaries and splits at dashes/ellipsis while counting
that punctuation. Malformed sections roll back their entire contribution.
`bookWordsOf` calls `measureTextOutline` again only to locate back matter.
Crossings already owns kept/in-flight outlines by edition/file revision, and
every `SpeechPair` already carries its outline. Its `words` callback currently
passes only the text edition through main.dart to `bookWordsReader` and the
BookSearch worker. This is settled reuse/extraction, with no product fork.

Use one section traversal for the shared visible-character rule and text-run
offsets. Keep word normalization/tokenization in its existing owner and outline
measurement/cache ownership in Crossings. Feed the existing outline through
the actual speech read job instead of measuring it again. Preserve first-ID
offsets, navigation/CFI behavior, Unicode and UTF-16 units, whitespace, entities,
CDATA, inline/block boundaries, punctuation, empty/malformed sections, missing
resources and back-matter exclusion. Preserve current body-event semantics;
this ticket does not redefine visibility as CSS visibility or rendering.
The worker must capture only transferable data, keep its existing cache/revision
identity, remain off the UI isolate and never persist admission/conversion data.
Preserve the download hold and remove/read rules. No global cache or second
outline owner, no speech-anchor persistence or place-map redesign.

Read `docs/plans/bookfin.md` and `docs/plans/cross-edition-places.md`. Likely owned
paths: speech/book_words, reader/book_map and text_outline, reader platform
factories, crossings speech wiring, the narrow main.dart callback and tests.
Audit all callers before choosing the smallest internal interface. Preserve
the integrated section stylesheet and admitted-record changes. Another ticket
may remove gallery startup branches in main.dart; do not duplicate its work.

Required proof: meaningful failing-then-passing behavior/work-count tests for
avoiding repeat outline measurement through a real worker read, and broad
agreement of speech offsets with book-map/outline offsets under the cases
above. Exercise EPUB and prepared MOBI reopen plus actual Crossings speech
landings, cache reuse and file-revision changes. Preserve existing worker and
write-ownership evidence. Counts establish avoided work, not Android latency.
Nix checks: focused speech/book_words, book_search, reader/book_words_reader,
text_outline/book_map and crossings speech tests; affected reader, crossings,
speech and app suites; full Flutter suite; changed-file format and affected
analysis/diff checks. Flutter concurrency two and one heavy command per owner.
One Astra xhigh lead builds/fixes, exactly one fresh read-only Astra high
reviewer assesses the complete diff. No second review, device/browser work,
coverage, mutations, publication or closure. Parent integrates and closes.

## Implementation evidence — 2026-11-13

Initial worktree inspection, before edits:

- Worktree: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-7d45a221`.
- Branch: `t3/share-visible-text-walk`.
- HEAD and original review base: `a85c8789e9a14c4d978f94e64db3c6cacfafd8a0`.
- Status: clean, with no prior implementation commits or edits.
- `tk ready` lists this in-progress ticket. `tk dep tree boo-j7gh` has no dependencies.
- Read project AGENTS.md, both plans, builder instructions, software-design,
  test-driven-development and its test-writing reference. No CLAUDE.md exists
  in this worktree. Ticket remains in progress; the parent owns integration.

Caller audit and implementation:

- `countSection` serves BookMap ID measurement and `measureTextOutline`.
  Both now use `walkSection` in `reader/section_text.dart`. Speech uses that
  same traversal and its text-run offsets. Only speech owns word splitting,
  inline/block boundaries, normalization and back-matter word limits.
- The shared traversal counts non-whitespace UTF-16 units. It preserves
  first-ID offsets before the body, text and CDATA from the first body start
  onward, text after the body end, and all-or-nothing malformed-section results.
  It does not apply CSS visibility. `text_outline.dart` re-exports the existing
  whitespace predicate for its PDF caller and the exhaustive whitespace test.
- Crossings still owns outlines and their retained/in-flight work. All three
  SpeechPlaces readers pass `pair.outline` through the single ReadEditionWords
  signature. The narrow main.dart callback passes it under the existing
  Downloads read. Both platform factories accept it. The IO factory captures
  only the path, digest, outline and top-level admission reader for BookSearch.
- `bookWordsOf` requires the owned outline and no longer measures it. There is
  no fallback outline measurement or new outline cache. BookSearch's two-book
  cache and Crossings' edition/file-revision keys are unchanged.
- All production and test callers of `bookWordsOf`, `bookWordsReader` and the
  speech callback were inspected. No production admission, persistence,
  conversion, download, anchor or place-map code changed. Admission revision 6
  and section CSS dependencies remain intact. No gallery startup edits.

Behavior evidence:

- Before implementation, a real BookSearch worker ran the real word parser
  over actual admitted section bytes. A test map counted two section reads
  per section instead of the required one. The test failed with expected
  `[1, 1]`, actual `[2, 2]`. After the change it passes and also proves that
  the job runs outside the calling isolate. This is work-count evidence,
  not an Android latency measurement.
- Ten hand-counted cases passed against the original implementation before
  extraction, and still pass: surrogate pairs/combining marks/numbers, every
  whitespace code unit, entities, CDATA/inline text, punctuation boundaries,
  empty sections, first IDs and post-body text, CSS-hidden body text, no body,
  and malformed sections. Additional tests cover missing section bytes and
  rollback in the middle of a book. Existing navigation/CFI tests are retained.
- EPUB and prepared/reader-converted MOBI reads now run through BookSearch in
  tests. An unprepared MOBI still fails without writing. An unsendable download
  hold proves that the factory does not capture the lent file. A reopened EPUB
  respects the supplied back-matter boundary and leaves every file byte intact.
- An actual Crossings landing uses the real platform reader and BookSearch.
  A repeated endnote does not win. Another place in the same revision still
  lands after both the source contents and admitted directory are removed.
  A new revision measures once and lands at the new offset. A new Crossings
  instance uses the retained outline without measurement and reopens the words.

Full command output is retained under `.cache/boo-j7gh/` in this worktree.
These ignored logs remain available to the reviewer and parent. Exact commands,
results and limitations follow after the required checks finish.

Required checks (all commands ran in this worktree through its Nix dev shell):

| Check | Exact command | Result | Log under `.cache/boo-j7gh/` |
| --- | --- | --- | --- |
| Meaningful red | `nix develop --command flutter test --concurrency=2 --reporter expanded test/speech/book_search_test.dart --plain-name 'a worker reads each section once'` | Exit 1, expected `[1, 1]`, actual `[2, 2]`; no compile/reference failure | `red-worker.log` |
| Original offset behavior | `nix develop --command flutter test --concurrency=2 --reporter expanded test/speech/book_words_test.dart` | Exit 0, 16 passed before production edits | `baseline-offsets.log` |
| Green worker and offsets | `nix develop --command flutter test --concurrency=2 --reporter expanded test/speech/book_words_test.dart test/speech/book_search_test.dart` | Exit 0, 24 passed | `green-core.log` |
| Focused checks | `nix develop --command flutter test --concurrency=2 --reporter expanded test/speech/book_words_test.dart test/speech/book_search_test.dart test/reader/book_words_reader_test.dart test/reader/text_outline_test.dart test/reader/book_map_test.dart test/crossings/speech_landings_test.dart` | Exit 0, 88 passed. Repeated after strengthening the cache test and adding the unsendable hold, again 88 passed | `focused.log`, `focused-final.log` |
| Affected suites | `nix develop --command flutter test --concurrency=2 --reporter expanded test/reader test/crossings test/speech test/app` | Exit 0, 1,893 passed, 21 existing skips | `affected.log` |
| Initial analysis | `nix develop --command flutter analyze lib/reader lib/speech lib/crossings lib/main.dart test/reader test/speech test/crossings test/app` | Exit 1, one new missing-braces lint in the integration test; fixed with braces | `analyze.log` |

The optional corpus, public trial-book and benchmark tests retain their existing
skip conditions. No timing threshold changed. The Flutter commands also report
that the `iphoneos` and `iphonesimulator` SDKs are absent; the host tests still run.
No device or browser check, coverage, mutation, publication, merge, or closure
ran. Android device blocker t1-dth0 and browser PDF blocker t7-3j9c were not
retried. Known intermittent t5-rplx and tf-il7u are not treated as explained by
any passing run.

The first full-suite run exposed one missed callback in the playback History
fixture: `test/playback/crossing_history_test.dart:435` still accepted one
argument. This was an implementation-caused compile failure, not a meaningful
red test or an intermittent failure. The fixture now accepts the owned outline
as its second argument. A repeated audit of every speech configuration under
lib, test, integration_test and tool found no other caller. Caller search output
is retained in `callers.txt` beside the logs.

| Check | Exact command | Result | Log under `.cache/boo-j7gh/` |
| --- | --- | --- | --- |
| First full suite | `nix develop --command flutter test --concurrency=2 --reporter expanded` | Exit 1: 3,538 passed, 27 existing skips, one load failure from the missed playback fixture callback | `full.log` |
| Playback callback fix | `nix develop --command flutter test --concurrency=2 --reporter expanded test/playback/crossing_history_test.dart` | Exit 0, all 12 passed | `playback-callback.log` |
| Final analysis | `nix develop --command flutter analyze lib test` | Exit 0, no issues across all production and test files | `analyze-final.log` |
| Changed-file format | `nix develop --command dart format --output=none --set-exit-if-changed lib/reader/section_text.dart lib/reader/book_map.dart lib/reader/text_outline.dart lib/reader/platform_io.dart lib/reader/platform_stub.dart lib/speech/book_words.dart lib/crossings/crossings.dart lib/crossings/speech_places.dart lib/main.dart test/reader/section_publication.dart test/reader/book_words_reader_test.dart test/speech/book_words_test.dart test/speech/book_search_test.dart test/crossings/speech_landings_test.dart test/playback/crossing_history_test.dart` | Exit 0, 15 files, 0 changes | `format-check.log` |

The initial formatter used the same path list except the subsequently found
playback fixture, without `--output=none --set-exit-if-changed`. It exited 0,
formatted 14 files and changed 9 (`format.log`). The full suite also retains
optional research measurements and three live-plugin integration skips.

Final full-suite command:
`nix develop --command flutter test --concurrency=2 --reporter expanded`.
Result: exit 0, 3,550 passed, 27 existing skips (`full-final.log`). No failure
was retried without a code fix: the only failed full run was the missed fixture
signature above. No failures from t5-rplx or tf-il7u appeared in these runs, and
these passing runs do not explain those intermittent failures.

The complete original-base-to-working-tree diff passes
`git diff --check a85c8789e9a14c4d978f94e64db3c6cacfafd8a0`.
The staged diff is checked again before the implementation commit. There are
no open forks. Implementation and required checks are complete; the one fresh
read-only reviewer remains the next stage.
