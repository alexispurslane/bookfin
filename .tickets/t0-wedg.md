---
id: t0-wedg
status: open
deps: []
links: []
created: 2026-11-13T01:40:12Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Give the host channels to an engine that the audio service starts before any Activity

Found by reading code during boo-zyx1 on November 12. Nothing was run, so this is not confirmed on a device.

MainActivity.configureFlutterEngine adds HostPlugin (HostChannels.kt) and OcrPlugin (OcrChannel.kt) to the Flutter engine. audio_service 0.18.19 can create that engine without an Activity: AudioService.onCreate calls AudioServicePlugin.getFlutterEngine, which makes the engine, registers only the generated plugins, and runs the Dart entrypoint at once. The service is exported as a MediaBrowserService and has a media button receiver, so Android can start it after the process ended, for example for a headset button or for the media resume player of the system. In that start, Dart runs with no bookfin/* channel. createDownloads (lib/downloads/platform_io.dart) then catches the missing channel and gives UnavailableDownloads for the life of the engine, and the listens on bookfin/media-network and bookfin/power fail. A later Activity adds the plugins, but Dart does not ask again.

First confirm it on a device: stop the app process, start playback from a media button or the resume player, then open the app and look at Downloads. A possible fix is to make the host channels a local Flutter plugin package, so that the generated registrant adds them to every engine. That also covers OcrPlugin. Before boo-zyx1 the same gap existed with the channels in MainActivity.

