---
id: boo-gcu6
status: in_progress
deps: []
links: []
created: 2026-11-12T23:41:00Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Write the settings of each record domain only when they change

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/playback/store.dart:900-913, 1216-1225 and 1444-1458. The listening settings and the reading settings share one account row. After the user changes the view setting of one PDF, `_smallSettings` returns false. From then on, every listening save (about one for each media-second) and every sync acknowledgment starts an isolate through `compute`, then encodes and rewrites the reading settings again. Store the settings of each domain separately and write them only when they change. Related closed ticket: boo-lj72.


## Parent caller audit and settled scope — 2026-11-13

At 15942f1c, ResumeStore._persist still encodes the combined metadata for SQLite commits, including unrelated nested reading settings; the existing scalar-only fast path rejects those maps. Native commits also update record_accounts metadata alongside journal changes. Preserve the existing ResumeStore/RecordDatabase ownership while storing each domain's settings independently and persisting only actual settings changes. A record-only save or upload acknowledgment must not encode or rewrite unchanged reading/listening settings. Keep durable settings and journal changes in one transaction when both change. No new writer abstraction or parallel pending-action inventory.

Use the current record journal, incremental current-state restore, commit encoding and reconstruction paths. Preserve old native database and preference migration, account isolation, settings restore, listening/reading snapshots and caller compatibility, pending records, retained unreadable originals, conflicts, deletion state, cursors, corruption retain-and-report, and retry after failed commits. A failed write must not mark settings as durably saved. Explicit recovery/reconstruction may rewrite whole state, but normal updates must not. Keep browser preference compatibility and its atomic whole-account limitations honest. Expensive settings comparisons/copies must not replace the avoided encoding with equivalent repeated UI-isolate work.

Own playback/store.dart, database.dart and narrowly necessary domain save wiring/tests. Reuse settled per-domain settings ownership rather than redesigning all record writers or typed record APIs (boo-n7no/boo-w6m2). Show a meaningful old-code failure with real SQLite operation/encode counts after nontrivial PDF settings exist, then verify listening saves, sync acknowledgments, actual settings changes, failure/retry, migration and reopen. Counts measure work; no Android latency threshold or timing claim.

Required Nix checks: focused real-file regressions, sync/playback/durability/app and affected reader/settings suites, full Flutter suite, affected analysis/format/diff. Concurrency two, one heavy command per owner. Astra xhigh implementation/direct fixes, exactly one fresh read-only Astra high reviewer; preserve original verdicts and resolve findings with evidence. No devices/browser, coverage, mutations, push, PR or closure. Parent owns integration, acceptance and closure.
