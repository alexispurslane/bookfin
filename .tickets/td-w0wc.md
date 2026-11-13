---
id: td-w0wc
status: open
deps: []
links: [boo-x1zf]
created: 2026-11-13T01:42:34Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Report a failed records refresh after a sync by its own cause

Found during boo-x1zf. Nothing was run for this finding. Status: confirmed by reading. Since boo-x1zf, `Playback.refreshPersonalRecords` passes a store failure to its caller, as `ReaderSession.refreshPersonalRecords` always did. `RecordSync` in lib/sync/coordinator.dart handles that failure with code that was written for other failures. (1) In `_sync`, `_cause` reads every FormatException as `RecordSyncFailure.pluginMissing`. A FormatException from the decode of a saved record inside a refresh then shows the banner that says the Bookfin Storage plugin is missing. (2) In `resolve`, one catch covers the save of the choice and the two refreshes after it. A refresh that fails after `records.resolve` saved the choice shows the message that the choice was not saved. Give the refresh step its own failure: the records on this phone could not be read (`RecordSyncFailure.unreadable`), and a choice that was saved stays reported as saved. A failed refresh leaves its domain stale, so the next sync refreshes it again.


## Notes

**2026-11-13T02:08:53Z**

Fixed by the second change of boo-x1zf. The orchestrator closes this ticket. What changed. RecordSync in lib/sync/coordinator.dart has one helper, _refresh, for the refreshes after a sync, after a choice and after a retry of kept copies. Each refresh is independent: a refresh that fails with an Exception stops neither the other refresh nor the caller, and the two refreshes run at the same time. In _sync, a failed refresh ends the sync as RecordSyncFailure.unreadable, whatever the type of the Exception, so a FormatException from a saved record no longer shows the plugin-missing banner. The outcome keeps the number of replaced records, and the choices are still shown. In resolve, a failed refresh after a saved choice reports nothing by itself. The sync that follows refreshes the stale domain again and reports how that ended, so the message that the choice was not saved appears only when no choice was saved. recoverKept reports nothing, as before. The store keeps a domain stale until its writer accepts a snapshot (_behind in lib/playback/store.dart), and synchronize returns staleDomains, so the next sync refreshes the domain of a failed refresh. No failure kind was added. Tests: 9 new tests in test/sync/refresh_after_sync_test.dart, of which 8 failed before the fix, and the expectation of the first change moved from RecordSyncFailure.other to RecordSyncFailure.unreadable.
