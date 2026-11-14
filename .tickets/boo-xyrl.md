---
id: boo-xyrl
status: closed
deps: [boo-pwx7]
links: [boo-6bge]
created: 2026-11-07T15:30:28Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Clear local data after uploading unsynced personal records


## Notes

**2026-11-13T21:43:34Z**

Parent asked the user on 2026-11-13 whether Clear data applies to the current account or every account previously used on this phone. Both designs preserve personal records, require confirmation, upload unsynced records before clearing downloaded files/covers/saved library, and stop on a required upload failure. All-account clearing may need credentials for prior accounts. This scope choice is pending; no implementation lead started. Existing approved behavior is docs/plans/bookfin.md, Library redesign, Clear data.

## User decision and implementation scope — 2026-11-13

The user selected the current account. Confirm the action through shared glass,
upload its unsynced personal records first, then clear only that account's
downloaded files, covers and saved library. Retain personal records and all other
accounts. A failed required save or upload stops removal. Bind the action to the
account that was confirmed; a later account change must never redirect it.

The user also selected deferred removal of a playing audiobook (boo-39cu): keep
playing, then remove after a saved pause or book switch. Reuse Downloads' removal
ownership for Clear data; do not bypass its active-read/playback protection with
a recursive deletion. Coordinate integration with boo-39cu, without inventing a
second pending-removal mechanism. Test real persistence and failure ordering.

Parent owns integration, device acceptance, hardening and closure. No device or
live account action is needed to implement and verify the host behavior.

## Launch accepted — 2026-11-13

Base: `2f5f0393d4d5961627b7eb84f7c2f7725ab762aa`.
Task ID: `node:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-boo-xyrl-astra-20261113-1`.
Child thread ID: `thread:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-boo-xyrl-astra-20261113-1`.
Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-boo-xyrl-astra-20261113-1>
Client request ID: `bookfin-boo-xyrl-astra-20261113-1`.

Lead: codex/gpt-6-astra xhigh. Stages: build, one read-only review
(codex/gpt-6-astra high), fixes if needed, then parent integration.
Launch reports running; branch and current stage have not yet been reported.
Parent retains integration, acceptance, hardening and closure.

**2026-11-13T23:23:14Z**

Implemented current-account Clear data in this bound worktree. New Downloads.clearAccount uses public remove/removeRetained and a beforeRemoval callback to recheck required record saves/uploads after file holds end. Initial required failure removes nothing; later failure stops further removal and never reports completion. Parent must integrate boo-39cu without bypassing this callback or the awaited public removal future. No playing-audio pending mechanism was duplicated. Catalog refresh retirement, scoped cover cleanup, atomic cache deletion, and account/credential guards are covered by real-store tests. Detailed logs and all failed attempts are in docs/evidence/boo-xyrl. Follow-up t5-23yk records pre-existing engine-rule issues; td-tswb records the acceptance fixture interface addition. Full suite and JS build verification are in progress; no ticket closure.

Implementation verification complete: focused 62 passed; final affected 777 passed/3 external skips; full Flutter 3900 passed/27 existing optional skips at concurrency 2; all 28 changed Dart files formatted and analyzed cleanly; production and gallery JavaScript release builds passed. Exact commands, complete logs including failures, source manifests, skip inventory and build hashes are retained in docs/evidence/boo-xyrl. Single independent review remains before readiness.

The single independent review of f8565faaf390fe5cf968909f8b8e6d8a764d6483 returned fail for correctness, fulfillment and design. Its original report is preserved verbatim in docs/evidence/boo-xyrl/reviewer-original.md. R1 (a failed live save during upload) and R2 (storage protection ending before catalog publication) were reproduced and fixed by this lead. R3's source-manifest summary was corrected. Focused fixes pass 91 tests; all 28 changed Dart files analyze cleanly; affected suites pass 1240 tests with three optional external skips. A new full suite and both release JS builds are required on the fixed source before readiness. No second review and no ticket closure.

Final integration boundary: Downloads.clearAccount retains its existing beforeRemoval preservation callback and now awaits an afterRemoval continuation while download requests stay blocked. Covers.clear likewise keeps loads blocked through its afterRemoval continuation. CatalogController.clearSavedLibrary supplies the guarded final cache removal/publication to its removeFiles callback. Preserve this one operation lifetime and the awaited public remove/removeRetained boundary when integrating boo-39cu; its playing-audio pause/book-switch behavior still belongs to that peer and parent integration.

Final fixed-source validation complete: full Flutter 3912 passed/27 unchanged optional skips; affected 1240 passed/3 external skips; focused 91 passed; analysis clean for all 28 changed Dart files; production and gallery release JavaScript builds passed. Review findings R1/R2/R3 are resolved with reproductions and evidence in docs/evidence/boo-xyrl/review-resolutions.md; original verdicts/report are unchanged. All owned commands and the single reviewer finished. Ready for parent integration checks, acceptance and hardening; ticket remains in_progress until parent integration and closure.

**2026-11-13T23:59:32Z**

Parent integrated f8565faa and e5c045fe as c8cc9e44 and 33837083. The only conflict was ticket-note append context; both parent launch notes and child notes are retained. Application/test sources match the child final HEAD exactly. Parent inspected the full diff, original failed review and recorded resolutions, independently verified all 39 command archives and 497 source hashes, and reran 120 focused tests on main: all passed, no skips. Source identity retains the relevance of the child full suite (3912 passed, 27 optional skips), analysis and both JavaScript builds. Evidence: docs/evidence/boo-xyrl/integration/integration.json. Ticket remains in progress for combined boo-39cu verification, acceptance and hardening; no closure or native acceptance claimed. No product decision remains.

**2026-11-14T00:44:15Z**

Clear data now passes combined tests with deferred audiobook removal: required pause saves and record uploads precede removal; failed saves/uploads retain files; book changes keep the next playing book protected. The operation still affects only the confirmed current account. Parent combined verification completed on committed source 0cd68d30f0b962d35b28289c2027b82b3f4e255d: 243 focused tests passed; 2012 affected tests passed with 3 existing skips; full Flutter suite passed 3974 tests with 27 unchanged skips and zero failures. Full lib/test analysis found no issues; 38 changed Dart files passed formatting; production and gallery JavaScript builds passed. All final checks used identical source bytes. Complete parent commands, logs, source snapshots, failures, skip comparison and integration resolutions are archived in docs/evidence/boo-39cu/integration/integration.json. Original reviews and lead resolutions remain unchanged; no second review. Implementation is merged and ready for closure. Native acceptance remains unverified in boo-6bge, blocked by t1-dth0; coverage/mutation and release hardening remain in boo-gk92. Closing this implementation does not claim device acceptance or release completion.
