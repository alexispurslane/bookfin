---
id: boo-8xyn
status: closed
deps: [boo-7z9a]
links: [boo-7z9a]
created: 2026-11-12T23:41:01Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Keep one copy of the catalog on the UI isolate

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed, size estimated. lib/catalog/controller.dart:268-276. The controller keeps the frozen entry maps (`_cache.entries`), the encoded text (`_text`) and the built library. On the UI isolate only `checkInvariants` reads the entries. The estimate is 20 to 30 MB for 1478 books, and it grows linearly. Keep the account facts and the built library, and let the worker read the entries again when it rebuilds. The corrections store ticket makes this natural.

## Parent caller audit and settled scope — 2026-11-13

At `96645868`, the survey's assertion that only the invariant checker reads
entries is outdated. After boo-7z9a, `_adoptChoices`, `_selectLibraries` and
`_edit` also send `_cache.entries` to correction or visibility workers.
`_Built` currently returns the full CatalogCache, text and derived library.
Restore, refresh and access revision therefore leave decoded server entries
reachable from the controller even after the worker finishes. Public `cache`
callers in library_view.dart and settings/screen.dart only need cache presence;
two tests read presence or accessBlocked. Audit all callers again while editing.

Follow this ticket's existing direction: retain saved catalog text, the small
account/catalog facts needed by orchestration, choices, and the built library.
Decode entries inside the existing worker when a correction or visibility
change rebuilds the library. Worker results must not keep the decoded server
entry graph alive on the UI isolate. This is a representation change inside
the current catalog owner, not a new catalog service. Keep one adoption path
for related facts, text and derived library. Replace the exposed full cache
with the narrow query its actual callers need; do not return an incomplete
CatalogCache that falsely represents an empty catalog. Preserve the on-demand
invariant check by deriving from the retained text without retaining its decode.

Preserve correction/visibility behavior from boo-7z9a: user choices remain in
their own durable store; changing choices never re-encodes or rewrites the
server catalog; known library visibility changes need no network; unknown
libraries still refresh. The worker decode for these rebuilds is the intended
tradeoff of this ticket, superseding the earlier decoded-entry input assertion.
Preserve unchanged-refresh library/book identity and narrow notifications,
cache-first startup, hidden-library retention, empty catalogs, expired sign-in
and denied-access distinctions, migration/recovery, account/request generation
guards, serialized writes and storage uncertainty after cancelled/failed writes.
Do not put large decode/hash/build work on the UI isolate. Keep the existing
measured small-work rule unless new evidence requires a change.

The 20–30 MB survey figure is an unmeasured estimate, not an acceptance result.
The pinned Dart SDK shares immutable strings and Isolate.run returns through
Isolate.exit; see tool/evidence/boo-hjal/README.md and dart-transfer.txt. Audit
actual Flutter compute behavior before claiming transfer savings. Prove the
removed retained entry graph and worker input/result boundaries with controlled
tests plus source/caller inspection; do not equate this with measured heap or
Android launch latency. Avoid a production diagnostics framework solely for
tests. No persistent-worker framework, format migration or extra cache is
needed for the settled scope. Report a real user-visible fork if one emerges.

Own lib/catalog/controller.dart, narrowly necessary catalog metadata/query
changes, the two UI presence-query callers, and affected catalog/settings tests.
Use existing real worker instrumentation in catalog_signals_test.dart and
choice/account race tests in choices_test.dart. Prove meaningful boundary
failure before implementation, then preserve behavior through restore,
refresh, correction, visibility and access revision. A missing API, source-text
comparison or test merely repeating a field declaration is not sufficient.
Run focused catalog/signals/choices tests, affected catalog/settings/app/
downloads/playback/sync tests, the full Flutter suite, changed-file formatting,
affected analysis and complete original-base diff check. Use Nix, concurrency
two and one heavy command at a time. One Astra xhigh lead and exactly one
fresh read-only Astra high reviewer; parent owns integration and closure.
No device/browser checks, coverage, mutations or timing-threshold changes.

## Launch — 2026-11-13

Astra xhigh lead launched from `6a5e2b95fa449be40c8de74431718346fb85b180`.
Running, stage uncertain; branch not yet reported. Exactly one fresh read-only
Astra high reviewer authorized. Parent integrates and closes.

- clientRequestId: bookfin-boo-8xyn-astra-20261113-1
- taskId: node:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-boo-8xyn-astra-20261113-1
- childThreadId: thread:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-boo-8xyn-astra-20261113-1
- Link: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-boo-8xyn-astra-20261113-1>

## Implementation checkpoint — 2026-11-13

- Worktree: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-b2f263a5`.
- Branch: `t3/catalog-worker-facts`.
- Initial HEAD and original review base:
  `6a5e2b95fa449be40c8de74431718346fb85b180`; initial status clean.
- Read the parent audit, all worker/adoption/choice callers, both UI cache
  callers, both test cache callers, and the derived library's retained fields.
  No prior production edits or commits were present in this worktree.
- The controller now retains catalog facts, encoded text, choices and derived
  books. Worker results contain no CatalogCache. Corrections and visibility
  decode the retained text inside their existing worker. `hasCatalog` replaces
  public full-cache access. The invariant checker decodes only on demand.
- Boundary red: five meaningful failures (restore, refresh and access revision
  returned entries; correction and visibility sent entries). Boundary green:
  eight passed. Focused signals/choices: 109 passed.
- Pinned Flutter 3.47.4 native compute uses Isolate.run. Dart 3.13.3 shares
  immutable strings; Isolate.run exits with its result without copying. Web
  compute uses the current event loop. No heap, launch or latency claim.
- Detailed caller audit, checks and saved output: `tool/evidence/boo-8xyn/`.
  Remaining verification and sole read-only review are recorded there before
  handoff. Parent retains integration, acceptance, hardening and closure.

Required build checks completed before review: affected suites 1,563 passed,
three opt-in skips; full Flutter suite 3,554 passed, 27 skips, no failures;
changed-file formatting zero changes; affected analysis no issues. All commands
used Nix, test concurrency two and one heavy command at a time. No device,
browser, coverage, mutation or timing-threshold work. The only failed test run
was the required meaningful red boundary run. See logs 01–08 and skips.txt.

## Sole review completed — 2026-11-13

Reviewed implementation: `e4fbdcddb6f2494c6d6fd751475368f6fe957e10`.
One fresh codex/gpt-6-astra high reviewer returned pass separately for
correctness, ticket fulfillment and software design, with no findings, gaps or
material unverified requirements. Original report and nonblocking limits are
preserved in `tool/evidence/boo-8xyn/review.json`.

Reviewer: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3Aaf33d308-0851-4e9f-ac09-b638017176d7%3Adelegate-task%3Abookfin-boo-8xyn-sole-review-20261113-1>

No fix or reapproval was needed. No production/test changes followed review.
The complete original-base-to-reviewed-head whitespace check passed; evidence
is `10-reviewed-head-whitespace.json`. Evidence-only final checks cover the
complete staged diff and final HEAD, including all saved logs. No fork remains.
All owned commands and the reviewer finished. Ready for parent integration;
parent retains acceptance, hardening and closure. Ticket is not closed here.

## Parent integration — 2026-11-13

Verified clean child checkout, branch and HEAD. Inspected the complete
original-base production/test diff, actual adoption and UI callers, concrete
retained metadata and derived-book fields, original review and saved red/green
and required outputs. No integration finding. Child `e4fbdcdd` integrated as
`2528c6ea`, and `1d2ad6b` as `27dc49fd`. A ticket-history conflict retained
both the parent launch record and the child evidence. Production and tests are
identical to the reviewed child implementation; no second review claimed.

Combined with corrupt-admission repair `583cae18`, the parent ran ten-file
format verification (zero changes), full analysis of lib/test/integration_test
(no issues), and catalog/settings/app/downloads/playback/sync/reader/crossings/
speech suites (3,435 passed, 24 existing skips, zero failures). Exact commands
are recorded in `.tickets/t7-vq21.md`; output is under
`/tmp/bookfin-ownership-catalog-{format,analysis,affected}.log`. The full suite
then passed in the same sequential Nix driver: 3,606 passed, 27 existing skips,
zero failures, exit 0. Full output is
`/tmp/bookfin-ownership-catalog-full.log`; driver output is
`/tmp/bookfin-ownership-catalog-driver.log`. All parent commands finished.
Complete integration and final ticket whitespace checks passed. No retry or
unexpected failure occurred. Parent closes this implementation ticket on main.
No heap-size, device latency, native acceptance or hardening claim is made;
existing platform blockers and unexplained intermittent failures remain open.
