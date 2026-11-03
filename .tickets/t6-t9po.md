---
id: t6-t9po
status: in_progress
deps: []
links: [boo-3oq0]
created: 2026-11-02T23:08:38Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Save personal-record changes incrementally while retaining every update

User-selected scope: store personal-record changes incrementally under the existing record owner, retaining every immutable action, including superseded resume updates. Avoid parsing/replaying and rewriting the entire retained action history for each ordinary save or acknowledgment. Keep current records, pending status and causal coverage coherent in durable transactions. Preserve the current server API/action format and all existing sync protections. No checkpoints, compaction, coalescing, automatic expiry or fixed lifetime storage claim. Coordinate with boo-3oq0; no competing hardening job.


## Notes

**2026-11-03T02:12:53Z**

Read-only builder investigation after plugin milestone 96d69c1, not a journal redesign. Added bounded opt-in host measurement using the actual Playback owner, real LocalResumeStore and durable SQLite. Twenty synthetic 100 ms source-position samples produce two saves/new pending actions over 2000 source ms. Five profiles retain 60/600/3600/21600 resume actions plus history, explicit deletions, reading, unresolved conflict and a causal gap. Eight timed saves after two warmups: offline medians 5.61/15.79/83.40/492.05 ms. At 21600 retained resume actions with only 16 pending identities, median remains 477.84 ms. Host debug/test figures, not Android performance. Every original action and pending identity survives restart. Evidence tool/evidence/sync/journal-growth.json and journal-growth-checks.txt; doc docs/research/personal-record-journal-growth.md reports two unselected designs and costs: incremental retained action rows versus versioned causal checkpoints. No compaction, checkpoint, expiry, sync-contract change, user-visible choice, hardening or ticket closure. Full project suite 407 pass/3 opt-in skips, analysis clean. Parent design decision/integration still required.

## Investigation integrated, decision pending

Main integrates read-only measurement23341c8 as1cb395f. No production journal
change. Parent will ask whether to retain all internal position actions with
incremental writes, or also summarize safely acknowledged superseded position
actions through a versioned protocol. Both preserve history, bookmarks,
unsynced actions, deletion barriers, causal gaps and unresolved conflicts.

## User decision — November 3, 2026

The user selected Design A: reduce save work only, write changes individually,
and retain every internal update. Continued storage growth is an accepted cost.
This supersedes the original checkpoint-oriented ticket description and the
unselected alternatives in the retained investigation. Implement migration,
transaction failure/retry, restart, causal-gap, conflict, deletion and account
isolation regressions. Measure ordinary saves and acknowledgments against the
retained-history profiles without claiming an Android latency bound.

**2026-11-03T12:27:44Z**

Implemented user-selected Design A from d69cfb3c63146939fc120454216fd0977059e645. LocalResumeStore remains the sole transition owner. SQLite v2 stores every immutable action individually and commits changed current-version identities, pending flags, causal coverage and metadata transactionally. No compaction, coalescing, checkpoints, expiry or plugin/API change. Lazy per-account migration validates every retained value, preserves pending identities and cursor, and rolls back to the intact old payload on failure. A failed mutation discards only its account cache so a retry reloads durable state. The retained journal is cached: first load/restart and memory still grow with all retained history across loaded accounts; the preference-only fallback deliberately retains previous recovery and whole-payload behavior.

Meaningful reds: two real SQLite-trigger failures prove the base rewrites retained account payloads during saves/sync; a further red proves held-action replay can reorder concurrent versions and falsely reject a valid restart. Canonical current-version identity sets fix that false rejection without modifying action payloads. Eleven actual-persistence tests cover v1 upgrade, migration rollback/repair, failed/retried position writes and acknowledgment, restart, held deletions, reordered/cross-installation dependencies, late uploads and immutable duplicates. Existing coordinator/player choices and account-return/rejected-refresh races run with both SQLite and preferences. Full project suite: 425 pass, 3 opt-in skips. Analysis: no issues. Bounded opt-in measurement and unchanged actual plugin regression pass separately, all through Nix, sequentially. Exact logs and source hashes are in tool/evidence/sync/incremental-*.txt/json and journal-growth-incremental.json; design/cost report: docs/research/personal-record-incremental-storage.md.

Final host save medians for 60/600/3600/21600 retained resume actions: 1.59/1.26/1.45/1.24 ms; the 21600-resume/16-pending profile: 1.75 ms. Ten saves insert ten action rows, with ten metadata/current/coverage changes each and zero retained payload updates/deletions. One-pending upload+ack+discovery medians including loopback HTTP: 5.90/5.93/5.71/5.21 ms. Fully pending migration+first-read: 16.07/33.50/130.50/666.87 ms; normalized warm-filesystem restart: 5.76/17.82/79.89/427.56 ms. Every original action/pending identity and protected state survives restart. No Android latency/battery/flash or finite lifetime claim. Actual unchanged Bookfin.Storage_0.1.1.0.zip SHA256 3b0de5ca1df39baf67c786079898b1ee3b0b09d3bdb86d00ece8a7f5731a9105 passed with two durable ordinary-account clients on disposable Jellyfin 12.4.0. Owned server stopped; 7464/7465 free. No Android/device/acceptance-port action, live service, PR, publication, coverage/mutation campaign, ticket closure or children. Independent parent review, integration and paused Android acceptance remain outstanding; this is not acceptance.

## Independent review and integration

Independent static review of d69cfb3..53e4d57 found no actionable blocker in
correctness, selected ticket scope, or design. Main integrated as 4ae8c6c with
no conflicts; its complete tree matches the reviewed candidate. Supplied 425
passes / 3 opt-in skips, clean analysis and actual-plugin evidence remain valid
for that identical tree; no redundant full-suite rerun. A fresh normal Android
build and matching source export are prepared under the integrated commit.
Android migration/process-death/memory and user acceptance remain pending;
prior 27bf44e APKs do not test this storage implementation. Ticket stays open.
Device work remains paused after the earlier repeated device-command failure,
awaiting renewed user authorization. No device interaction performed here.
