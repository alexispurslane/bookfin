---
id: boo-hd47
status: in_progress
deps: []
links: []
created: 2026-11-12T23:41:01Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Compute the contents entries of each EPUB section once, not at each page turn

## Settled scope — 2026-11-13

The existing prepared section owns the facts derived from its DOM. Prepare the section's applicable contents locations and fallback heading once with that section, then use them when reporting a shown page. Keep URL resolution, heading traversal and contents-location derivation off the repeated page-report path. Reuse existing worker preparation and section lifetime/eviction paths; do not add a global cache, another source of chapter-title truth, or a general indexing framework. Full and partial preparation, excerpts, settings changes, eviction and reopen must retain coherent ownership.

Preserve current chapter-title semantics: package-relative paths and decoded fragments; entries without fragments; missing or malformed targets; CFI ordering; last equal-position entry wins; heading fallback; Chapter N fallback; 512-character limit. Use meaningful red-green behavior and work-count evidence for repeated page reports with many contents entries, not host timing thresholds or Android latency claims. Inspect actual consumers before deciding the smallest internal interface. The existing ownership model settles this work; report only a genuine product fork.

Owned scope: EPUB preparation/places/pager and narrow source wiring/tests, this ticket. Preserve boo-rcgf's paragraph-width ownership and active excerpt lifetime. Required Nix checks: focused regression/places/pager/preparation tests, reader and crossings suites, affected analysis/format, full Flutter suite. Concurrency two, one heavy command at a time. Implementation and direct fixes Astra xhigh; one fresh read-only Astra high reviewer, no second reviewer. No device, browser, coverage, mutations, push, PR or closure; parent owns integration and closure.

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: path confirmed, cost estimated. lib/reader/epub/pager.dart:761-777 and lib/reader/epub/places.dart:237-276. Each reported page turn resolves the URL of every contents entry in the book, walks the section DOM for a heading, and scans all text nodes with `indexOf`. A book with thousands of contents entries (a Bible, collected works) spends an estimated 2 to 10 ms for each turn on the UI isolate. lib/reader/epub/search.dart:232-253 already filters entries by section. Compute the entries and the heading once for each prepared section.

## Launch — 2026-11-13

Astra xhigh lead launched from 00b5860e7cdabcc943871913409036646900bd13; running, stage uncertain. One fresh read-only Astra high reviewer authorized.

- clientRequestId: bookfin-boo-hd47-astra-20261113-1
- taskId: node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-hd47-astra-20261113-1
- childThreadId: thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-hd47-astra-20261113-1
- Link: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-hd47-astra-20261113-1>

## Parent prerequisite steering — 2026-11-13

The launch base includes download integration before the parent fixture/ordering corrections were committed. Sent the running lead explicit authorization to cherry-pick parent commit 7cb281777c991f4e05fd4b731ba70bd3ba7a2971 before broad/full verification. It carries the corrected catalog-only credential fixture, sync repair retention and account notification ordering, with regressions. These are parent-owned prerequisites, not EPUB implementation. Lead must record the prerequisite SHA separately, exclude it from the ticket's own review attribution/implementation commit list, preserve owned edits, and report any conflict instead of overwriting. The parent will skip the duplicate prerequisite at integration. Steering returned delivered/running; no child status was polled.

## Implementation and verification — 2026-11-13

Owner: ticket lead, Astra xhigh, in the T3-created worktree
`/Users/alexispurslane/.t3/worktrees/bookfin/t3-4b9a8cd2`. Initial branch was
`t3/4b9a8cd2`; later inspection showed
`t3/reuse-epub-contents`. No checkout was
created, reset or switched. Original review base:
`00b5860e7cdabcc943871913409036646900bd13`.

Parent prerequisite: explicitly authorized cherry-pick of
`7cb281777c991f4e05fd4b731ba70bd3ba7a2971`, applied without conflict as
`64d9fede7d5806941d7194941915dd3c57206ec6`. Its six non-EPUB files are parent
integration input, not this ticket's implementation. The parent must skip this
prerequisite when integrating this ticket's own commits. No parent-reported
verification counts are claimed below.

`PreparedSection.chapters` owns chapter facts derived from its DOM. Whole and
partial worker preparation supply the publication contents and package path.
The same-parse fallback from part to whole and note excerpts reuse those facts.
Different parses retain the existing section/settings cache lifetime and eviction
rules. `ChapterTitles` resolves contents targets and the fallback heading once;
page reports and search hits query the same title rule. Sorted CFI steps retain
contents order for equal positions. Saved quotes locate their text-list suffix
without a linear scan over earlier text nodes. No global cache, new indexing
framework, test-only production hook, width-measurement owner or excerpt-lifetime
change was added. No product fork remained.

New domain tests exercise chapter names and saved quotes, package-relative paths,
decoded fragments, malformed and missing targets, CFI ordering and last equal
entry selection. Existing places and saved-place fixtures retain fallback and
length-limit checks. New lifetime tests cover partial preparation, the same-parse
whole fallback, note excerpts, worker handover, eviction, settings changes and
reopen. Existing reader tests cover boo-rcgf's width and active excerpt rules.

All commands below run in this worktree. Logs are in `.cache/boo-hd47/`.
Only one build/test command ran at once; Flutter concurrency was at most two.

- Meaningful red: `nix develop --command flutter test --concurrency=2 --reporter=expanded test/reader/epub/chapter_titles_test.dart`.
  `red.log`: two intended failures. `red-complete.log`: three intended failures
  and one passing semantics test, before production changes. Thirteen page
  reports read 26,013 contents hrefs on the reporting path; 60 chapter-title
  queries read 120,120 hrefs; the late quote read 4,002 text-list entries.
- The first focused implementation run failed to compile because the new
  `chapters` field was mistakenly declared in a local scope. This was corrected;
  `focused-green.log` preserves that failure. This is not meaningful red evidence.
- `focused-green-2.log`: 174 passed, two skipped after that correction.
- Focused final command: `nix develop --command flutter test --concurrency=2 --reporter=expanded test/reader/epub/chapter_titles_test.dart test/reader/epub/places_test.dart test/reader/epub/prepare_test.dart test/reader/epub/section_part_test.dart test/reader/epub/pager_test.dart test/reader/epub/page_source_test.dart test/reader/epub/search_test.dart test/reader/epub/saved_places_test.dart`.
  `focused-final.log`: 193 passed, three optional tests skipped. Work counts:
  13 reports read zero hrefs; one worker prepare read 2,001 hrefs. Sixty title
  queries used 2,002 href reads, two target lookups and one heading traversal
  total. The late quote needed 14 text-list reads. These are controlled operation
  counts, not host timing thresholds or Android latency measurements. The read
  counter uses the existing injected worker boundary inline; a separate test
  exercises actual isolate handover for partial and whole preparations.
- Initial affected analysis (`analysis.log`) reported three `avoid_print` infos
  in new test diagnostics. The final analysis result is recorded below.

SDK discovery prints missing `iphoneos` and `iphonesimulator` warnings on this
host. Tests run on the Flutter host tester; no device or browser work, coverage,
mutation testing, push, PR, merge, deployment or ticket closure was performed.
Parent owns integration, acceptance and hardening.

Further checks:

- `nix develop --command flutter test --concurrency=2 --reporter=expanded test/reader test/crossings`:
  `reader-crossings.log` finished with 1,673 passed, 21 skipped and one failure:
  `test/reader/unread_records_test.dart:97`, "the next place after a failed read
  opens the records again without a flush", expected one resume and got none.
  Existing ticket `t5-rplx` records the same intermittent failure. This test
  constructs ReaderSession directly, without the EPUB pager. No reader-record,
  test-wait or parent prerequisite code was changed for it.
- `nix develop --command flutter test --concurrency=2 --reporter=expanded test/reader/epub/chapter_titles_test.dart test/reader/unread_records_test.dart`:
  `focused-unread-retry.log`, all 13 passed. The unread-record test is unchanged.
  New test diagnostics now use stdout, resolving the lint issues without
  changing behavior. This retry confirms an intermittent occurrence, not its cause.
- `nix develop --command flutter analyze lib/reader/epub/places.dart lib/reader/epub/prepare.dart lib/reader/epub/page_source.dart lib/reader/epub/pager.dart lib/reader/epub/search.dart test/reader/epub/chapter_titles_test.dart test/reader/epub/places_test.dart test/reader/epub/saved_places_test.dart test/reader/epub/page_source_test.dart`:
  `analysis-final.log`, exit 0, no issues.
- `nix develop --command dart format --output=none --set-exit-if-changed lib/reader/epub/places.dart lib/reader/epub/prepare.dart lib/reader/epub/page_source.dart lib/reader/epub/pager.dart lib/reader/epub/search.dart test/reader/epub/chapter_titles_test.dart test/reader/epub/places_test.dart test/reader/epub/saved_places_test.dart test/reader/epub/page_source_test.dart`:
  `format-final.log`, exit 0, nine files, no changes.
- Reader/crossings retry of the same command: `reader-crossings-retry.log`,
  exit 0, 1,674 passed and 21 skipped. The unread-record recovery test passed.
- `git diff --check`: exit 0; `diff-check.log` is empty.
- Full suite: `nix develop --command flutter test --concurrency=2 --reporter=expanded`:
  `full.log`, exit 0, 3,491 passed and 27 skipped, including the unchanged
  unread-record recovery test. Every required build check is now complete.

Review gate: implementation is ready for the single authorized fresh read-only
reviewer, Astra high through `delegate_task`, shared isolation, async, role review.
The reviewer must inspect the full original-base diff, separate the parent
prerequisite from this ticket, read callers and logs, and assess correctness,
fulfillment and design independently. Integration remains with the parent.
