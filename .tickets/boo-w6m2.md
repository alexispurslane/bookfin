---
id: boo-w6m2
status: open
deps: []
links: [boo-rw9z, boo-2bl9, boo-n7no]
created: 2026-11-12T23:41:00Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Return typed records from the record store and refresh only what changed

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: code path confirmed, size estimated. lib/playback/playback.dart:1016-1055 and 610-629. The store hands Playback the whole listening snapshot as `Map<String, dynamic>`. Playback decodes every history event on the UI isolate at each bind and at each refresh after a sync, and it branches on snapshot versions 1, 2 and 3. History has no size limit (tb-5fyd), so the cost grows linearly, on the order of 100 ms on a phone at 10,000 events. The worker of the store returns typed records, and a query for the records changed since the baseline of a writer makes a refresh cost proportional to the change.

