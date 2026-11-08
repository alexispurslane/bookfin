---
id: tc-qdk7
status: closed
deps: [td-rvpm]
links: []
created: 2026-11-07T23:56:52Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-bquq
tags: [ui-rules]
---
# The open listening timeline relabels its rows when the library changes

Found in t9-d4kb. ListeningTimeline follows only Playback.recordsNotifier. Its labels and place times come from Playback.editionTime, which reads the bound library. A library refresh with the same account changes no records, so an open timeline keeps its old labels until the next records change or until it opens again. Before t9-d4kb the timeline followed every Playback change. Playback has no narrow library signal. Give Playback a library signal, or make the timeline entries change when the library changes, then let openListeningTimeline merge it into the entries listenable in lib/playback/timeline.dart.

## Acceptance Criteria

With the timeline open, a library refresh that changes the length of an earlier file updates the place times of the shown rows. A playing tick still rebuilds no row.


## Notes

**2026-11-08T00:12:38Z**

Orchestrator, Nov 7: one agent does tc-qdk7, t9-cx1u and boo-uceu together (group A), to save agent cycles on playback.dart and the broad notifications.
