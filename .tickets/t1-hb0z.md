---
id: t1-hb0z
status: closed
deps: [t9-cx1u, tc-qdk7]
links: []
created: 2026-11-08T00:45:00Z
type: task
priority: 4
assignee: Alexis Purslane
parent: boo-bquq
tags: [ui-rules]
---
# Merge the hand-written derived ValueListenable classes into one

Rules: UI rule 2 (one component for each kind of thing).

Five private classes repeat one shape: a ValueListenable whose value is read on demand from a source, and whose listeners go to that source's notifier.
- lib/catalog/library_services.dart, _ShelfLayoutView
- lib/playback/timeline.dart, _TimelineEntries
- lib/playback/screen.dart, _EditionShare
- lib/playback/recent.dart, _PlaybackRecent (added by t3-da6r)
- lib/development/gallery.dart, _SampleShare

Target design: one small public type in lib/foundation, for example a ValueListenable built from a Listenable and a read function, with equality by source where an owner rebuilds. Each of the five becomes one use of it.

## Acceptance Criteria

- The five classes are gone, and each use builds the shared type.
- Tests show that each use still notifies only on its own source.


## Notes

**2026-11-08T00:51:59Z**

Orchestrator, Nov 7: waits for group A (tc-qdk7, t9-cx1u), because group A changes _TimelineEntries in lib/playback/timeline.dart and Playback's signals.
