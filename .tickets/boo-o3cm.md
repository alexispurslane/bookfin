---
id: boo-o3cm
status: open
deps: []
links: []
created: 2026-11-12T23:41:01Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Keep download records across a library change and bind Playback without waiting for the scan

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/downloads/local_downloads.dart:220-244 clears `_records` and scans the whole download tree again whenever the bind signature changes. The signature covers every source, so any library change, and every launch, shows "Not downloaded" for every book until the scan ends. The scan costs about 20 asynchronous filesystem operations for each source directory. lib/app/account_binding.dart:121-123 awaits it before `playback.bind`, so the restored book waits. Key the records by source id, compare the old and new source sets at a bind, read only the new ids, and drop only the removed ones. `localFile` already waits for each source, so Playback can bind at once. Related: boo-tapn.

