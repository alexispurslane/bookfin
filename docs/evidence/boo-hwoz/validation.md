# boo-hwoz validation

## Ownership and starting state

- Worktree: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-92207740`.
- Branch: `t3/narrow-collection-queries`.
- Original base and initial HEAD: `0c0984d98f8d2e9b4be7f39e9a10769ddee0bf9c`.
- The initial working tree and index were clean. No checkout was created,
  switched, reset or removed. `tk start boo-hwoz` retained in-progress status.
- Parent owns integration, acceptance, hardening and closure. No merge, push,
  PR, deployment, device/browser check, server access, credential request,
  coverage, mutation test or timing-threshold change was performed.

## Source and caller audit

Current research version: Jellyfin 12.4, pinned by
`tool/research/sync/flake.nix:10` and source revision
`83d0d0e7f76e23e2e085c8ff67d28b772d35967d` in
`docs/research/jellyfin.md:665`. The plan's 10.11 reference is historical.
The ten source captures in the two parent manifests were SHA-256 verified;
`source-hashes.txt` records the hashes and pinned source URLs.

At the current revision, `ItemsController.cs:290-308` derives linked-child
ancestor IDs from the supplied library parent for BoxSet queries. Line 454
puts those IDs on the internal query. Lines 592-596 dispatch through the
selected folder's `GetItems`; lines 626-629 return the caller's start index.
`Folder.cs:1140-1162` filters direct children before final sorting and paging.
`BoxSet.cs:132-147` uses the folder child path and preserves collection order
and user visibility. `DtoService.cs:1177` assigns the core item ID, while
`ItemFields.cs` has no `Id` option. Image and user-data flags are accepted via
DTO options. These observations are source evidence, not a live-server test.

On 10.11, `ItemsController.cs:274-278` ignores the library parent for BoxSet
queries. `Folder.cs:970-1002` pages children before filtering and retains the
unfiltered count; `AddChildrenFromCollection` at 1347-1380 applies the source
page boundary. The new walk therefore advances by the requested source page
size through the reported count, including empty filtered pages. It never
changes direct membership into recursive membership.

`CatalogController._refresh` is the production caller of `catalog`
(`lib/catalog/controller.dart:1127`). It already chooses shown book libraries,
handles empty selections, owns request generations and saved-library adoption,
and retains the catalog worker from boo-zs5i. Its public interface and cadence
are unchanged. Test adapters call the same method from catalog signals,
library visibility and choices tests. `catalogEntries` adds memberships to
admitted item IDs. `model.dart:_seriesOf` intentionally gives plain Audio
tracks no series label even though their collection membership is retained.
No production caller outside `lib/catalog/jellyfin.dart` needed alteration.

## Scope and fixture evidence

- Collection discovery is scoped to each shown library, in batches of four.
  Collection IDs are deduplicated before child reads. Old servers can still
  return global discovery results without repeating child reads.
- Discovery and child reads use bounded 200-item pages and validated counts,
  starts and IDs. Counts outside 0 through 1,000,000 and changing counts are
  rejected. Discovery must be dense; children may be sparse for 10.11.
  Child reads retain batches of at most eight collections.
- Membership requests accept AudioBook, Book and Audio, omit optional image
  and user data, and do not send `fields=Id`. No retained membership cache or
  cadence change was added. Every catalog call fetches memberships anew.
- Optional collection failures still yield a usable catalog without collection
  series. Cancellation still reaches the caller. An error listener is attached
  immediately to the parallel collection read, avoiding an uncaught rejection
  while library reads are pending.

The loopback fixtures cover mixed collections, two shown libraries sharing a
collection, hidden libraries, unrelated movie collections, all three admitted
item types, preserved direct membership, and the existing Audio-track series
rule. They also cover 1,001 collections, 4,001 matching children on the current
shape, and 4,002 source children on the old shape: one early book, 4,000 movies,
and one late book. The old shape has a short first page, empty middle pages,
and a late-page book. Other cases cover no shown libraries, renamed/removed
membership between refreshes, unavailable collections, cancellation while
changing accounts, credential rejection, malformed replies, changed counts,
repeated pages and truncated collection discovery.

The mixed fixture receives 140 membership-response bytes. The same three
records with the optional image and user fields would occupy 389 bytes in
that fixture. It receives zero non-book child records and makes one child
request, despite discovering the shared collection in both shown libraries.
The corrected red run against the original code receives three non-book child
records. These are fixture measurements only. They establish neither live
latency nor a universal memory or request-count improvement. On 10.11,
library-scoped discovery remains unsupported by the server.

## Failures retained during implementation

1. `red.log`: 8 passed, 10 failed against original production code. Nine failures
   were missing paging, narrowing or validation behavior; the mixed-collection
   test initially expected an Audio track to gain a series label, contrary to
   existing product behavior.
2. `green-narrowing.log`: 2 passed, 1 failed because of that fixture expectation.
   The expectation was corrected without changing the Audio-track rule.
3. `red-narrowing-corrected.log`: the corrected fixture failed against the
   original production file on actual non-book payload: expected 0, received 3.
4. `focused.log`: 48 passed, 1 failed with an uncaught `Refresh cancelled`
   rejection in the collection/account transition test. Immediate error
   observation fixes the parallel-future ownership gap. The focused cancellation
   check and complete focused suite subsequently pass. The failure is retained;
   a passing retry alone is not presented as proof of its cause.
5. `affected.log`: 1,664 passed, 3 skipped, 1 failed.
   The old `_ServerTransport` in `library_visibility_test.dart` answered BoxSet
   queries with library books. The new library-scoped query exposed that fixture
   defect: it recorded item IDs `heard` and `read` as queried libraries. The
   fixture is updated to return its actual empty collection list. The affected
   suites then passed: 1,665 tests, with 3 existing plugin-integration skips.
6. `analyze.log`: one unnecessary non-null assertion in the new paging helper.
   Removing it changes no behavior; Dart proves the value is non-null at return.

Initial formatting before dependency resolution warned that flutter_lints
could not be resolved. The first test command resolved dependencies. Host
Flutter commands print missing iphoneos/iphonesimulator SDK diagnostics;
these are not device tests and did not prevent the host checks from running.

## Full-suite failure investigation

The first full run reproduced `tf-il7u` in
`test/reader/epub/page_source_frames_test.dart:188`: the deep-page request had
completed when the test expected it to remain pending between scheduled
frames. The preceding poll-count assertion did not fail. The failure has the
same message as the existing ticket: "idle steps ran in a row between frames".
Neither that test nor `lib/reader/epub/page_source.dart` differs from the
original review base. The test starts the deep-page request before mounting
its continuously redrawing widget; the existing ticket records investigation
of that ordering as unfinished. This source inspection does not establish the
cause of the intermittent result. No scheduling code or timing threshold is
changed. Full original failure details and later check outcomes remain in the
machine-log summaries and command inventory.

The full run completed with 3,673 passed, 27 skipped and this one failure.
The unchanged focused frame suite then had 4 passes and the same failure.
A third run temporarily restored `lib/catalog/jellyfin.dart` verbatim from
the original base, then restored the implemented file afterward. This restored
all production code to the original base for that focused run: Jellyfin is
the only modified production file. The original-production run also had
4 passes and the same failure. This proves that the failure can occur without
this ticket's production change, not why it occurs. No full-suite success is
claimed. `t5-rplx` did not fail in this run; its cause also remains unknown.

The final affected analysis passes with no issues. Changed-file formatting
passes without changes. The final catalog run passes 56 tests after restoration of the
implemented production file. Detailed commands and original logs follow.

## Checks and review

Exact commands, outcomes, failures, skips and full log paths are in
`commands.json`. Complete logs are retained under `/tmp/bookfin-boo-hwoz`.
The original reviewer report is preserved as `review.json` without rewriting
its verdicts, findings or gaps. Acceptance and hardening stay with the parent.

## Review resolution

Exactly one fresh codex/gpt-6-astra reviewer at high effort completed the
read-only review of `5055f01314fe443e255efd14fbda49df282304dd` against the
original base. Its completed thread was read before saving the report.

Reviewer: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3Ace22c3c2-4bc0-421a-8632-9d8553a10032%3Adelegate-task%3Aboo-hwoz-review-astra-high-20261113-1>

| Assessment | Original verdict | Resolution |
| --- | --- | --- |
| Correctness | pass | Original evidence and limits retained. |
| Ticket fulfillment | changes-required | D1 recorded as linked follow-up t9-ftlz, as the review explicitly permits. |
| Design | changes-required | Same D1 resolution; no second reviewer or revised verdict. |

AGENTS.md:39 says to fix a touched engine-rule violation or record a ticket.
The review explicitly allows that route for D1. The new ticket t9-ftlz records
the whole-list collection processing that still runs on the UI isolate, where
it happens before the controller's worker handoff, its possible scale, and
acceptance for moving it off the UI isolate. Runtime delay remains unmeasured.
The deferral resolves this review obligation; it does not fix the CPU work or
establish that the work is harmless. `resolutions.json` preserves the decision
and every review gap, including the failed full suite and excluded checks.

Only tickets and evidence changed after review. Production and test files are
identical to the reviewed HEAD, so the earlier test, analysis and formatting
results still apply. No behavior fix required another red-green cycle.
The complete original-base diff is whitespace-checked again with the new
ticket and review evidence staged, and again after the final commit. Parent
integration and acceptance must retain the known tf-il7u failure and the
tracked collection-processing risk. No ticket was closed.

The first review-evidence whitespace check failed because `tk create` left an
extra blank line at the end of t9-ftlz. The log and failure are retained in
`commands.json`; the final correction removes that line and records the
successful complete original-base-to-final-HEAD check separately.
