---
id: boo-3y46
status: in_progress
deps: [boo-0931]
links: []
created: 2026-11-12T23:41:00Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Keep discovery going past a server object that this build cannot apply

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/playback/store.dart:504-512 and 546-549 throw a FormatException for a tombstone, or for an action value that this build cannot decode, before the cursor advances. The object stays on the append-only server, so every later sync on that device throws on the same page and the device receives no later record from any device. lib/sync/coordinator.dart:321-324 reports the failure as "plugin missing". test/sync/transport_test.dart:211 and closed ticket t9-of05 lock the throw in, so a change needs a user decision. Proposed model: keep the object, apply the rest in causal order, hide the unreadable value, report a count, and give the case its own failure kind. Skip tombstones, or remove DELETE from the plugin.


## Notes

**2026-11-13T01:09:38Z**

User decision, 2026-11-12: keep it, skip it, go on. The phone stores a record that it cannot apply, advances the cursor, receives everything after it, and shows a quiet count of records that need a newer Bookfin. The case gets its own failure kind, not pluginMissing. This reverses the stop that t9-of05 and test/sync/transport_test.dart:211 lock in, so that test changes with this ticket. Add a test for the sync after such a record.

## Astra implementation scope

Implement the recorded user decision on top of boo-0931's committed-current-state restoration. A valid discovery page may contain individual remote objects that this build cannot apply, including unknown versions or values, malformed individual payloads and server tombstones. Retain each such object's original payload and identity/sequence information durably for its account before moving the discovery cursor. Continue receiving later pages and the next sync; apply later readable records where their causal prerequisites are present. Never invent missing predecessors, turn a server tombstone into permission to erase local history, or weaken immutable duplicate checks. Existing valid unknown kinds must remain hidden and retained for a future build.

LocalResumeStore owns the durable transition and retention; RecordTransport owns wire parsing; RecordSync owns scheduling and outcome reporting. Commit received records, retained unreadable objects and cursor together, or commit none. Repeated delivery must not lose records or inflate the count. Keep a quiet per-account count in the existing Sync UI and give unreadable remote records their own outcome/failure kind, separate from a missing plugin. Preserve raw data for a future build or retry; do not delete or coalesce it. Malformed whole-page boundaries, unsafe cursors, local database failures and absent plugin routes still report their actual failure rather than being silently skipped.

Preserve bounded native startup from boo-0931, all retained originals, its recovery protections for deletions/conflicts and accepted server copies, boo-s11s batching and grouped acknowledgments, and boo-hmrp local-first upload scheduling. No plugin protocol/deployment change is needed. The concurrently running boo-721h owns the local-account/credential distinction; do not duplicate it. Parent resolves integration overlap.

Required meaningful red-green evidence includes the rejected object between readable records, a later discovery page, the next sync, native reopen, retained raw payload equality, retry without duplicate counts, account isolation, transaction failure/rollback, local pending writes, unknown kind/version, malformed individual payload, server tombstone, and preserved causal gaps and conflicts. Exercise both legacy and batch transport paths and the quiet UI/status distinction. Update the old stop-on-malformed-remote test. Run sync, durability, playback, app and affected reader persistence tests; affected analysis/format; and the full Flutter suite at concurrency two through Nix, one heavy command at a time.

Implementation/direct fixes use codex/gpt-6-astra xhigh; exactly one fresh read-only reviewer uses Astra high. Parent owns integration, acceptance, hardening and closure. No device, coverage, mutation, push, PR or deployment work.
