---
id: boo-1fcy
status: open
deps: []
links: []
created: 2026-11-12T23:41:01Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Retry a download after a transient failure and keep long transfers alive in the background

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: code confirmed, the Android freeze is plausible and was not observed. lib/downloads/local_downloads.dart:1172-1187. A stream timeout, a connection reset or a 5xx without a reported network change sets `requested = false`, and the file shows "Download failed" until the user taps Retry. The manifest declares no data-sync foreground service and no WorkManager, so Android can freeze a transfer that runs without playback. Model a transient failure as "waiting to retry" with backoff. Keep terminal only the failures that need the user: 401 or 403, a length or identity mismatch, full storage. Run long transfers under a foreground data-sync service or WorkManager.

