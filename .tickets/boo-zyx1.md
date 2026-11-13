---
id: boo-zyx1
status: open
deps: []
links: []
created: 2026-11-12T23:41:01Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Own the network event channel for the life of the Flutter engine

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. android/app/src/main/kotlin/dev/bookfin/bookfin/MainActivity.kt:108-112 and 162-188. The ConnectivityManager callback and the event sink of `bookfin/media-network` are fields of the Activity, and `onDestroy` removes them. Under audio_service the engine outlives the Activity, and Dart subscribes once (lib/downloads/platform_io.dart:51), so after the user swipes the app away during playback no network change reaches Dart again. A download then continues on mobile data without the per-session consent, and a download that waits for Wi-Fi does not resume. Commit 5944606e fixed the same class of bug for `bookfin/power`. Register one FlutterPlugin for each engine that owns the connectivity callback and the power receiver. Also give the `pendingOffline` resume flag (lib/playback/playback.dart:763, 1693) a reader and a rule that clears it, or delete it. No production code reads it.

