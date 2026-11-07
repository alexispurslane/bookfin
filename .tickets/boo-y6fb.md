---
id: boo-y6fb
status: open
deps: []
links: []
created: 2026-11-07T21:36:12Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-bquq
tags: [performance, ui-rules]
---
# Give Playback a narrow position signal

Rules: UI rule 3 (a data source exposes narrow change signals). Engine rule 1 (comment only).

Breaks (verified at f388307):
- lib/playback/playback.dart, _accept: calls _notify on each 200 ms sample. Every Playback listener runs at that rate: PlayerView, PlaybackMiniPlayer, ListeningTimeline, ReplacementStartNotice, every library tile through LibraryServices.activity, the book page body, and the shell's selectors.
- lib/playback/native.dart, PlaybackHandler: playback.addListener(_publish) publishes the media session state on each tick.
- lib/playback/playback.dart: the sleep countdown has no signal, so PlayerView computes it from DateTime.now in build.
- lib/playback/playback.dart: the records (history, bookmarks and resumes) have no signal of their own. The timeline and the library progress need one.
- lib/playback/playback.dart, _decoderAnchor: jsonEncode on each save. This is small. Add the engine rule 1 comment that says why it stays inline.

Target design:
Playback keeps its ChangeNotifier and adds narrow listenables:
- position: the open edition's position, set by _accept and by seeks.
- sleep: the time left on the sleep timer, updated while it runs.
- records: changes when history, bookmarks or resumes change.
- selection: the open book and edition, and the playing state.

In this ticket the broad notification still fires on each tick, so every current listener keeps working. The widget tickets (t9-xj41, t9-sspn, t9-kfdf, t9-d4kb) move to the narrow listenables. Then t9-cx1u stops the broad notice on ticks. PlaybackHandler publishes the playing state on a selection change, and a position only on a seek or a state change, because the media session extrapolates the position from its update time and speed.

Owned files: lib/playback/playback.dart, lib/playback/native.dart, and their tests.

## Acceptance Criteria

- A playing tick notifies position, and does not notify records, sleep or selection.
- Play, pause, a seek and a book change notify selection or position.
- Adding a bookmark notifies records.
- The media session gets a playing-state change at once, and no update for a tick that changes no state.
- The old criterion moves to t9-xj41 and t9-cx1u: a playing tick rebuilds only the widgets that show the position.
