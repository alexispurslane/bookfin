---
id: boo-2bl9
status: open
deps: []
links: [boo-rw9z, boo-n7no, boo-w6m2]
created: 2026-11-13T08:23:18Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Keep record refresh from holding sync behind audio commands

Found during parent integration of boo-rw9z at 4c020d1e. Read-only evidence; no reproduction has been run. Playback.flush is now independent of unfinished audio commands, and its regression proves transport can exchange durable records while a seek is held. A later step remains coupled: RecordSync._sync awaits records.refreshWriters (lib/sync/coordinator.dart:391); the store awaits every stale writer (lib/playback/store.dart:241); Playback.refreshPersonalRecords uses _recordsCommand (lib/playback/playback.dart:619), which shares the audio command queue. When received listening records make Playback stale during a held audio command, the exchange can finish but the sync operation cannot. _exclusive retains _running until _sync returns, so later manual or background syncs also wait. This is a statically confirmed path; the trigger still needs a controlled regression.

Reproduce an exchange that receives a listening record while an audio command remains held, then request another exchange. Keep the received record durable, protect pending local changes, account/generation identity, revision checks and snapshot acceptance, and preserve clear sync outcomes. Use one coherent ownership model to keep durable sync progress independent of decoder completion while adopting live records safely. Decide the interface from these real callers before implementation; do not add a timeout or claim the records were adopted when they were not. Preserve the existing boo-rw9z flush contract. Related shared-writer and typed-record work may provide the same ownership boundary. Follow red-green TDD and existing single-review rules when scheduled.

