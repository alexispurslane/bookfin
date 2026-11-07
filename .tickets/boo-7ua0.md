---
id: boo-7ua0
status: open
deps: [boo-xifx]
links: []
created: 2026-11-07T21:34:40Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [performance]
---
# Skip work after a record sync that changed nothing

From the boo-nxp8 report. LocalResumeStore.synchronize returns void, so RecordSync cannot tell whether remote records changed. Make synchronize report whether it applied remote changes, and skip refreshPersonalRecords, the history re-parse and the listener notification when nothing changed. Also: _syncAccount in lib/main.dart listens to every catalog notification, even in the background, and calls synchronize() each time while verified. Subscribe it to the narrow signal it needs (UI rule 3) and let the RecordSync schedule own when syncs run.

## Acceptance Criteria

A sync that finds no remote change causes no notification and no re-parse. A catalog change that does not affect the account does not start a sync. Background syncs happen only through the RecordSync schedule.

