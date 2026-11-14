---
id: t0-wedg
status: closed
deps: []
links: [t0-5b9b, boo-zyx1]
created: 2026-11-13T01:40:12Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Give the host channels to an engine that the audio service starts before any Activity

Found by reading code during boo-zyx1 on November 12. Nothing was run, so this is not confirmed on a device.

MainActivity.configureFlutterEngine adds HostPlugin (HostChannels.kt) and OcrPlugin (OcrChannel.kt) to the Flutter engine. audio_service 0.18.19 can create that engine without an Activity: AudioService.onCreate calls AudioServicePlugin.getFlutterEngine, which makes the engine, registers only the generated plugins, and runs the Dart entrypoint at once. The service is exported as a MediaBrowserService and has a media button receiver, so Android can start it after the process ended, for example for a headset button or for the media resume player of the system. In that start, Dart runs with no bookfin/* channel. createDownloads (lib/downloads/platform_io.dart) then catches the missing channel and gives UnavailableDownloads for the life of the engine, and the listens on bookfin/media-network and bookfin/power fail. A later Activity adds the plugins, but Dart does not ask again.

First confirm it on a device: stop the app process, start playback from a media button or the resume player, then open the app and look at Downloads. A possible fix is to make the host channels a local Flutter plugin package, so that the generated registrant adds them to every engine. That also covers OcrPlugin. Before boo-zyx1 the same gap existed with the channels in MainActivity.


## Notes

**2026-11-14T16:42:57Z**

Confirmed on a device, 2026-11-14, private emulator bookfin-wedg-20261114 (Android 16), release build 0.1.1 (9a6b8efe) and tool/showcase_fixture.dart. Steps: sign in, download First Frost's audiobook, play 5 s, pause. dumpsys media_session then names Bookfin's MediaButtonReceiver as the last one. Kill the app process as root (kill -9, not force-stop). 'adb shell cmd media_session dispatch play' starts a new process 'for broadcast {dev.bookfin.bookfin/com.ryanheise.audioservice.MediaButtonReceiver}'. Dart logs 'MissingPluginException(No implementation found for method listen on channel bookfin/power)'. The play key plays nothing (PlaybackState stays NONE). Opening the app in the same process (pid 5541) shows Downloads: 'Local downloads are available in the Android app.' with no books, although First Frost is downloaded. Files stay on disk; a new process fixes it.

**2026-11-14T17:16:22Z**

Fixed, 2026-11-14. The device run showed two gaps, and both are closed.

1. Missing channels. HostChannels.kt, OcrChannel.kt and OcrWorker.java moved into the local plugin package packages/bookfin_host, and BookfinHostPlugin owns both channel sets. Flutter's GeneratedPluginRegistrant now adds dev.bookfin.bookfin.BookfinHostPlugin to every engine, also to the engine that the audio service makes for a media button. MainActivity is a plain AudioServiceActivity. The Kotlin package stays dev.bookfin.bookfin, so the JNI names of bookfin_ocr do not change.
2. A lost play. audio_service queues the media-button command until Dart configures it, then sends click, which calls PlaybackHandler.play() before attach(playback) and before Playback restores its book. The old play() was _playback?.playExternally(), so the command did nothing. PlaybackHandler now keeps a system play that finds no open edition and sends it when an edition appears, for at most 10 s. A pause or a stop forgets it. Tests: test/playback/media_session_test.dart, group 'a system play that comes before the book' (6 tests; 3 failed on the old code for the missing play).

Device check, private emulator bookfin-wedg-20261114, release-key build 0.1.3+1004 of this tree, tool/showcase_fixture.dart: play, pause at 39.9 s (PAUSED), kill -9 as root, cmd media_session dispatch play. A new process starts for the MediaButtonReceiver broadcast, logs no MissingPluginException, and reaches PLAYING at 39.9 s. Opening the app in that process (same pid) shows Downloads with First Frost's audiobook and EPUB, and the mini player playing. Not checked: a real Bluetooth headset, and the lock-screen resume card on the user's Pixel.

Verification: flutter analyze lib test, no issues. flutter test test/playback test/app, 703 passed. nix develop --command bash test/native/ocr_worker_test.sh, PASS. Debug and release Gradle builds pass with the plugin package.
