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

