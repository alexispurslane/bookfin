---
id: boo-zyx1
status: in_progress
deps: []
links: [t0-5b9b, t0-wedg]
created: 2026-11-12T23:41:01Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Own the network event channel for the life of the Flutter engine

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. android/app/src/main/kotlin/dev/bookfin/bookfin/MainActivity.kt:108-112 and 162-188. The ConnectivityManager callback and the event sink of `bookfin/media-network` are fields of the Activity, and `onDestroy` removes them. Under audio_service the engine outlives the Activity, and Dart subscribes once (lib/downloads/platform_io.dart:51), so after the user swipes the app away during playback no network change reaches Dart again. A download then continues on mobile data without the per-session consent, and a download that waits for Wi-Fi does not resume. Commit 5944606e fixed the same class of bug for `bookfin/power`. Register one FlutterPlugin for each engine that owns the connectivity callback and the power receiver. Also give the `pendingOffline` resume flag (lib/playback/playback.dart:763, 1693) a reader and a rule that clears it, or delete it. No production code reads it.


## Notes

**2026-11-13T01:41:33Z**

Built in commit bbd74032. HostPlugin, a plugin of the Flutter engine in android/app/src/main/kotlin/dev/bookfin/bookfin/HostChannels.kt, now owns every channel that MainActivity registered: bookfin/media, bookfin/speech, bookfin/device, bookfin/power and bookfin/media-network. It makes the channels, the connectivity callback and the power receiver when the engine attaches it, with the context of the application, and it removes them when the engine ends. MainActivity has no fields and no onDestroy. It only adds OcrPlugin and HostPlugin to an engine that lacks them. The application-owned PowerEvents object became a stream handler inside the same plugin, so both event channels follow one model. The Dart contract is unchanged: channel names, method names and event values are the same. The documents and comments that named MainActivity.kt as the owner of the channels now name HostChannels.kt.

Verification. `nix develop --command bash -c "flutter pub get && bash tool/bookfin build-android"` passed: Gradle assembleDebug built build/app/outputs/flutter-apk/app-debug.apk in 122.6 s with no Kotlin warning or error, the three package verify steps passed, and classes13.dex of the APK holds dev/bookfin/bookfin/HostPlugin. `nix develop --command dart analyze lib/downloads/platform_io.dart` found no issues. `nix develop --command flutter test test/downloads test/playback` passed, 618 tests. The project has no JVM or instrumented test setup under android/, so no automated test covers the Kotlin change. Not verified on a device: nobody swiped the app away during playback, reopened it and changed the network, on a phone or an emulator. The proof is the compile and the reading of the Flutter embedding: the stream handler and its sink now belong to the engine, and a new Activity does not replace them.

The pendingOffline flag is unchanged. The survey is right that the only production reader is Playback.pendingOfflineResume, that its only production caller is _save, and that no rule clears the flag. But docs/plans/bookfin.md, section Standard Jellyfin behavior, says: "Keep pending offline progress locally. Reconcile it with newer server activity before uploading." That sentence gives a purpose to what the flag marks, and no code builds that purpose. So the choice between a reader with a clearing rule and deletion is a product decision. Ticket t0-5b9b holds the findings and two designs.

New work found: when the audio service creates the engine before any Activity, no bookfin channel exists and Dart keeps unavailable downloads. This gap is older than this ticket. Ticket t0-wedg holds it. It came from reading code and was not run.

**2026-11-13T01:47:18Z**

Orchestrator, 2026-11-12: merged into main. A reviewer read the old MainActivity against HostChannels.kt line by line and passed correctness and design, with one comment fix that is applied: the comments now say that an engine that the audio service starts before any Activity has no plugin until an Activity attaches (t0-wedg, raised to priority 1). The ticket stays open until the device check runs: start playback, swipe Bookfin from Recents, reopen it, turn Wi-Fi off and on, and expect a Wi-Fi-only download to pause and then resume. The pendingOffline part moved to t0-5b9b, which needs a user decision.
