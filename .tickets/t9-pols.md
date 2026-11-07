---
id: t9-pols
status: in_progress
deps: [t9-se8f, t9-dcld]
links: []
created: 2026-11-07T22:09:38Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-bquq
tags: [ui-rules, engine-rules]
---
# Settings and record sync report actions to their page, and background syncs stay silent

Rules: UI rule 1 (only controllers cause side effects). UI rule 3 (depend on the minimum). Engine rule 2 (no labels or messages for a background refresh).

Breaks:
- lib/settings/screen.dart, DensitySwitch: writes layout.density itself.
- lib/settings/screen.dart, SettingsPage: reads the catalog and the layout as values, and relies on the shell's broad ListenableBuilder to update. The Personal-record sync route captures catalog.books when it is pushed, so the conflict names do not follow a library refresh.
- lib/sync/screen.dart, RecordSyncView: calls sync.synchronize and sync.resolve, and listens to the whole RecordSync.
- lib/sync/coordinator.dart, RecordSync.synchronize: each periodic background sync sets busy (the button reads "Syncing personal records…"), then "Personal records are synced." or a failure message. Engine rule 2 allows these only for a sync that the user started, or for a failure that blocks what the user is doing.

Target design:
- SettingsTab is the controller of the tab. It subscribes to the catalog's account and status listenables and to the layout density. DensitySwitch gets the density and reports onChanged.
- A RecordSyncPage controller owns Sync now and resolve. RecordSyncView becomes a leaf that gets the sync state and the catalog's library listenable and reports onSync and onResolve(record, identity).
- RecordSync tells a user-started sync from a background sync. It exposes narrow listenables: the status of a user-started sync or resolve (busy and message), and the conflicts. A background sync changes the conflicts. What else it shows is the open decision below.

Decided by the user on November 7, 2026: Option B. The Sync page shows a quiet line such as "Last synced 4:29 PM" or "Last sync failed. Tap Sync now to retry.", with no busy state during a background sync.

Former open decision: what the sync page shows after a background sync.
- Option A: nothing. Only Sync now and resolve show busy and a result. Cost: the user cannot see when the last background sync ran or that it failed, unless the user taps Sync now.
- Option B: a quiet line such as "Last synced 4:29 PM" or "Last sync failed. Tap Sync now to retry.", with no busy state during a background sync. Cost: a status line that a strict reading of engine rule 2 forbids, shown only on this page.

Owned files: lib/settings/screen.dart, lib/sync/screen.dart, lib/sync/coordinator.dart, and their tests.

## Acceptance Criteria

- A background sync shows no busy state and no "synced" message. Its result on the page follows the open decision.
- Sync now shows busy, then the result.
- DensitySwitch reports onChanged and writes nothing (a layout fake that throws on write).
- After a library refresh, the conflict list names the book from the new library.
- RecordSyncView calls no RecordSync method (a fake that throws proves it).

