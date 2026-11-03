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
# Bound production sync journal growth without discarding unsynced records

Production personal-record sync retains immutable operations, including superseded resume updates. Add a durable equivalent checkpoint or safely staged unsent resume representation, with causal-gap/retry/deletion/restart tests, before claiming lifetime storage bounds. Do not expire listening history. Coordinate this with boo-3oq0; no competing hardening job.


## Notes

**2026-11-03T02:12:53Z**

Read-only builder investigation after plugin milestone 96d69c1, not a journal redesign. Added bounded opt-in host measurement using the actual Playback owner, real LocalResumeStore and durable SQLite. Twenty synthetic 100 ms source-position samples produce two saves/new pending actions over 2000 source ms. Five profiles retain 60/600/3600/21600 resume actions plus history, explicit deletions, reading, unresolved conflict and a causal gap. Eight timed saves after two warmups: offline medians 5.61/15.79/83.40/492.05 ms. At 21600 retained resume actions with only 16 pending identities, median remains 477.84 ms. Host debug/test figures, not Android performance. Every original action and pending identity survives restart. Evidence tool/evidence/sync/journal-growth.json and journal-growth-checks.txt; doc docs/research/personal-record-journal-growth.md reports two unselected designs and costs: incremental retained action rows versus versioned causal checkpoints. No compaction, checkpoint, expiry, sync-contract change, user-visible choice, hardening or ticket closure. Full project suite 407 pass/3 opt-in skips, analysis clean. Parent design decision/integration still required.

## Investigation integrated, decision pending

Main integrates read-only measurement23341c8 as1cb395f. No production journal
change. Parent will ask whether to retain all internal position actions with
incremental writes, or also summarize safely acknowledged superseded position
actions through a versioned protocol. Both preserve history, bookmarks,
unsynced actions, deletion barriers, causal gaps and unresolved conflicts.
