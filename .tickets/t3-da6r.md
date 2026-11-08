---
id: t3-da6r
status: in_progress
deps: []
links: []
created: 2026-11-08T00:15:11Z
type: task
priority: 4
assignee: Alexis Purslane
parent: boo-bquq
tags: [ui-rules]
---
# Let RecentListeningList take values so the gallery can show it

Rules: UI rule 2 (one component for each kind of thing). UI rule 3 (depend on the minimum).

Breaks:
- lib/playback/recent.dart, RecentListeningList: it takes the whole Playback, so only a real Playback can feed it.
- lib/development/gallery.dart, _PlayerFixture: the gallery repeats its composition (the RECENTLY LISTENED label, then one RecentListeningRow per book that is not open).

Target design:
RecentListeningList takes a listenable of the recent entries with their progress, and the open book. The playback side builds that listenable from recordsNotifier and selectionNotifier. The gallery passes sample values.

Owned files: lib/playback/recent.dart and its tests, then lib/development/gallery.dart.

## Acceptance Criteria

- The player and the gallery both show RecentListeningList.
- RecentListeningList takes no Playback.

