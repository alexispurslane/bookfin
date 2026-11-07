---
id: t9-cx1u
status: open
deps: [boo-63ti, t9-sspn, t9-kfdf, t9-d4kb, t9-xj41, t9-8v91, t9-6u46, t9-dcld, te-20r5]
links: []
created: 2026-11-07T22:09:39Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-bquq
tags: [ui-rules, performance]
---
# Playback and Downloads stop broad notifications for position ticks and byte progress

Rules: UI rule 3 (a data source exposes narrow change signals instead of one notification for everything).

Breaks:
- lib/playback/playback.dart, _accept: calls _notify on each position sample, so every Playback listener runs five times a second.
- lib/downloads/local_downloads.dart, _download: calls notifyListeners on each byte step, so every broad Downloads listener runs during a transfer.

Target design:
This ticket runs after every consumer uses the position signal (boo-y6fb) and Downloads.watch. Then a position tick notifies only the position signal, and byte progress notifies only the watch of its edition. The broad notifiers fire for the playing state, the open book or edition, records, messages and phases. Search lib/ for each remaining broad listener and make sure that it needs none of the removed notices.

Owned files: lib/playback/playback.dart, lib/playback/native.dart, lib/downloads/downloads.dart, lib/downloads/local_downloads.dart, and their tests.

## Acceptance Criteria

- Ten playing ticks cause no notification on Playback's ChangeNotifier (counter).
- A transfer of ten byte steps causes no broad Downloads notification. phases notifies at the start and at the end.
- Every widget test passes, so each widget that shows a position or bytes still updates.

