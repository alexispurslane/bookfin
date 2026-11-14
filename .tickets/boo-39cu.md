---
id: boo-39cu
status: closed
deps: []
links: [boo-6bge]
created: 2026-11-12T23:41:01Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Keep playing and remove a requested audiobook after pause or book switch

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: plausible, the ExoPlayer reopen was not observed. lib/playback/playback.dart:1204-1210 takes file URIs from `downloads.localFile` without a lend, and `changeDownload` (lib/downloads/local_downloads.dart:690-699) waits only for work held through `readLocalFile`. A removal of the playing multi-file edition deletes the files under the player. The next file or a seek then fails with "Cannot play this local audio file". The position is saved. Playback uses the same lend as the reader, or the controller that confirms the removal stops that edition first. Related: t7-5m4d.


## Notes

**2026-11-13T22:12:19Z**

Parent asked the user on 2026-11-13 whether removing a playing audiobook should save its place, stop playback and remove files immediately, or keep playing and remove files when the user pauses or switches books. Both designs require confirmation, preserve personal records and stop removal on a failed save. The choice is pending; no implementation lead is running. The survey failure remains plausible until reproduced.

## User decision and implementation scope — 2026-11-13

The user selected: keep playing and defer removal until pause or book switch.
Keep the existing confirmation and show that removal is pending where needed.
Save the listening place before releasing the files. A failed required save
stops removal. Preserve History, bookmarks, saved places, and all unrelated
accounts/editions. Paused audio may be removed without starting playback.

Use the existing Downloads removal/read ownership and Playback command owner.
Make multi-file playback, seeks, pause, switch, account/source replacement and
asynchronous save/removal failures coherent. Do not make the UI widget own the
pending action. Establish the original failure with a controlled reproduction.

Concurrent boo-xyrl adds current-account Clear data. Keep Downloads' public
removal boundary usable by that action; it must receive the same active-audio
protection. Preserve the integrated Ask-at-Play and scoped playback notices.
Parent owns integration, native acceptance, hardening and closure.

## Launch accepted — 2026-11-13

Base: `2f5f0393d4d5961627b7eb84f7c2f7725ab762aa`.
Task ID: `node:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-boo-39cu-astra-20261113-1`.
Child thread ID: `thread:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-boo-39cu-astra-20261113-1`.
Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-boo-39cu-astra-20261113-1>
Client request ID: `bookfin-boo-39cu-astra-20261113-1`.

Lead: codex/gpt-6-astra xhigh. Stages: build, one read-only review
(codex/gpt-6-astra high), fixes if needed, then parent integration.
Launch reports running; branch and current stage have not yet been reported.
Parent retains integration, acceptance, hardening and closure.

## Implementation evidence — 2026-11-13

Worktree: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-06198e29`.
Branch: `t3/defer-audiobook-removal`.
Original base: `2f5f0393d4d5961627b7eb84f7c2f7725ab762aa`; initially clean.

The survey failure is now reproduced with real LocalDownloads files and a
test decoder that reopens them during a seek and multi-file progression.
Both preferences and SQLite reproduce missing files before the fix.

Downloads owns pending removal through its existing public removal boundary,
including retained files. Playback uses the reader's verified-file holds for
every audio part. Removal asks the current consumer to release outside the
Downloads command queue, so a book switch can obtain its new files. Playback's
command queue owns decoder pause, the required local save, and file release.
A failed save rejects removal and retains file ownership for an explicit retry.
The existing confirmation and narrow download status show pending removal.

`Downloads.remove(Edition)` keeps its signature. Its future resolves after
removal, not when the request is queued. Clear data must await that future and
treat failure as failure. `VerifiedFile.hold` adds an optional `beforeRemoval`
callback; providers of `VerifiedFile.lent` receive that callback as the second
argument of `hold`. Existing ordinary reader hold calls are unchanged.

Checks, exact commands, every failed run, source patches and SHA-256 hashes
are retained in `docs/evidence/boo-39cu/`. The full-suite results separately
list every skipped test. No coverage or mutation campaign ran. Native device
acceptance remains with the parent under t1-dth0; host callbacks and the
file-reading test decoder are not native device proof. No live server,
credentials, destructive account operation, browser or device was used.

Follow-ups recorded under this epic and dependent on integration of boo-39cu:
t0-dv5n (independent file verification currently uses the existing serialized
read queue), and t0-ejq2 (the pre-existing place-origin lookup suppresses
programming Errors). No performance measurement or runtime reproduction is
claimed for those static findings. Integration, acceptance, hardening and
ticket closure remain parent-owned.

**2026-11-13T23:38:52Z**

Pre-review checks complete: 36 new real-file lifecycle tests across preferences and SQLite, plus the pending-button widget test. Affected suite: 895 passed before the final two race cases; post-race focused ownership suites: 81 passed. Final full Flutter suite: 3868 passed, 27 existing skips, zero failures, concurrency=2. Scoped analysis: no issues. Production and gallery JavaScript builds pass. Format: 11 files, zero changes. Source/evidence hashes and all 29 verification commands are audited in docs/evidence/boo-39cu/verification.json. Earlier failures remain archived and explained in implementation.json. The queued-removal/failed-close race is reproduced and fixed. One fresh read-only reviewer is next; no readiness or integration/closure is claimed yet.

**2026-11-14T00:11:36Z**

The sole read-only review at 21aafcbe625319e0ed7d480a4aaee32453cf6ec4 returned changes required for correctness, fulfillment and design. Its original report is preserved verbatim in docs/evidence/boo-39cu/reviewer-original.json; metadata/link and per-ID resolutions are alongside it. BOO39CU-C1/C2/C3/C4/F1/D1 are fixed by this lead with failing reproductions and green focused checks; no second review was requested. A further failed-save close/retry bypass was reproduced on preferences and SQLite and fixed. Final affected checks: 994 passed. Analysis: no issues. Production/gallery JS builds pass. Full-suite verification is in progress. New static touched-code rule follow-up: t0-hwo8 (leftover inventory Error handling), dependent on this ticket. Existing t0-dv5n and t0-ejq2 remain. LeftoverFiles adds a default-empty removing set; Downloads.remove keeps its signature and must be awaited. One formatting command overlapped a stalled test during fixture repair; all incomplete runs and the sequencing deviation are explicitly retained in review-run-notes.json. Later verification runs are sequential.

**2026-11-14T00:17:14Z**

Review fixes verified: 50 real-file lifecycle tests across preferences and SQLite; focused lifecycle/status checks 95 passed; affected checks 994 passed. Final full Flutter suite through Nix, concurrency=2: 3883 passed, 27 unchanged skips, zero errors. Scoped analysis and production/gallery JavaScript builds pass. Final format check: 12 files, zero changes. All original review verdicts and IDs, resolutions, failures, interrupted fixture runs, exact commands, logs, patches and hashes are retained in docs/evidence/boo-39cu. No second review. No owned implementation gap remains; native acceptance, Clear data integration, hardening and closure stay parent-owned. Ticket remains in progress pending integration.

**2026-11-14T00:32:57Z**

Parent integration inspection found PARENT-R1: the narrowed Exception-only UI handlers exposed expected stale edition/retained-file guards as uncaught StateErrors. Run 06 reproduced both real confirmation flows after a catalog change. Parent changed expected catalog/ownership/storage failures to recoverable Exceptions; invariants and invalid hold usage remain Errors. Run 05 was a fixture-clock stall, interrupted only through its owned runner PID 82022; exit zero without a completion event is not a pass. Run 07 passed both new regressions and 100 other cases, but one existing private-storage assertion still expected StateError; it was updated to FileSystemException. Full final verification remains in progress. No second review.

**2026-11-14T00:44:15Z**

Parent integrated 21aafcbe and 1748f938 as a77cfd06 and 3413c099, preserving the complete current-account Clear data operation. Parent commit 0cd68d30 adds eight combined real-store cases and fixes expected stale-confirmation errors escaping recovery, with meaningful red evidence. Parent combined verification completed on committed source 0cd68d30f0b962d35b28289c2027b82b3f4e255d: 243 focused tests passed; 2012 affected tests passed with 3 existing skips; full Flutter suite passed 3974 tests with 27 unchanged skips and zero failures. Full lib/test analysis found no issues; 38 changed Dart files passed formatting; production and gallery JavaScript builds passed. All final checks used identical source bytes. Complete parent commands, logs, source snapshots, failures, skip comparison and integration resolutions are archived in docs/evidence/boo-39cu/integration/integration.json. Original reviews and lead resolutions remain unchanged; no second review. Implementation is merged and ready for closure. Native acceptance remains unverified in boo-6bge, blocked by t1-dth0; coverage/mutation and release hardening remain in boo-gk92. Closing this implementation does not claim device acceptance or release completion.
