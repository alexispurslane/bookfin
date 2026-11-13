---
id: boo-s11s
status: open
deps: [boo-hmrp]
links: [boo-f4xm, boo-0931, boo-hmrp, t6-il6y, t8-dqir]
created: 2026-11-12T23:41:00Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Upload and receive personal records in batches

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/playback/store.dart:458-489 sends one HTTP PUT and one local SQLite transaction for each pending action, oldest first. The plugin refuses a discovery page above 4 objects (plugin/Bookfin.Storage/StorageController.cs:24-27), and the client stops after 128 pages. One hour of listening queues about 3,600 actions. The next sync then makes 3,600 round trips in sequence, and the newest place arrives last. A receiving device takes at most 512 actions for each sync, and each cut-off sync reports "Sync did not finish". Step 1 needs no plugin change: upload with bounded concurrency and acknowledge each batch in one transaction. Step 2 changes the plugin API (a batch PUT and larger discovery pages, selected by plugin version). The November 3 decision in t6-t9po kept that API fixed, so step 2 needs a user decision.


## Notes

**2026-11-13T01:09:38Z**

User decision, 2026-11-12: do both steps, client first. Step 1: bounded concurrent uploads and one acknowledgment transaction for each batch, with no plugin change. Step 2: a batch upload and discovery pages of hundreds of objects, selected by plugin version, with the 4-object shape as the fallback. This replaces the part of the November 3 decision (t6-t9po) that kept the plugin API fixed. The decision to keep every action stays. Step 2 changes what t6-il6y (in progress) packages, so coordinate with that ticket.

## Integration prerequisites and package coordination

The parent inspected t6-il6y before launching this work. Its local deployment candidate is already integrated; that ticket remains open for deployment and broader acceptance, not for an active implementation branch. This ticket owns the additive batch API, its package version/metadata and documentation, and disposable compatibility evidence. Keep the existing plugin identity, database, retained actions, and v1 clients usable. Do not publish or install on a live server. Record the new candidate and exact compatibility evidence in t6-il6y when complete; its earlier 0.1.1.0 proof does not establish compatibility of the changed API.

The current transport is lib/sync/transport.dart after boo-f4xm. The store remains the durable acknowledgment owner; the event scheduler from boo-hmrp remains unchanged. Build and commit the client-only step before the additive plugin step so the fallback can be inspected separately. Use the pinned tool/research/sync dev shell and existing disposable plugin fixtures for C# and packaging checks. Preserve partial-success retry, account isolation, deletion barriers, conflicts, cursor transactionality, and every immutable action. No record compaction or startup snapshot work belongs here.
