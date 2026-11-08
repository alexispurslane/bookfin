---
id: boo-7ua0
status: open
deps: [boo-4bof, t9-pols, t9-dcld, boo-0km1, td-rvpm]
links: []
created: 2026-11-07T21:34:40Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-bquq
tags: [performance, ui-rules]
---
# Skip work after a record sync that changed nothing

From the boo-nxp8 report. LocalResumeStore.synchronize returns void, so RecordSync cannot tell whether remote records changed. Make synchronize report whether it applied remote changes, and skip refreshPersonalRecords, the history re-parse and the listener notification when nothing changed. Also: _syncAccount in lib/main.dart listens to every catalog notification, even in the background, and calls synchronize() each time while verified. Subscribe it to the narrow signal it needs (UI rule 3) and let the RecordSync schedule own when syncs run.

Owned files: lib/playback/store.dart (the synchronize result), lib/sync/coordinator.dart, and the file that holds _syncAccount after t9-dcld (lib/app/account_binding.dart or lib/main.dart), and their tests. Order: after boo-4bof (store), t9-pols (coordinator), t9-dcld and boo-0km1 (account binding).

## Acceptance Criteria

A sync that finds no remote change causes no notification and no re-parse. A catalog change that does not affect the account does not start a sync. Background syncs happen only through the RecordSync schedule.

## Notes

**2026-11-07T23:20:50Z**

t9-pols merged: RecordSync no longer extends ChangeNotifier; it publishes statusNotifier ((busy, message), user actions only), lastSyncNotifier ((at, failed)) and conflictsNotifier, and serializes syncs and choices through _exclusive. A background synchronize() shows nothing. Build the no-change skip on that.

**2026-11-08T00:12:38Z**

Orchestrator, Nov 7: one agent does tf-0nvi and boo-7ua0 together (group C), store and sync work.
