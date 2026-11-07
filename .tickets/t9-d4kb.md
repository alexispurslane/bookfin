---
id: t9-d4kb
status: open
deps: [t9-xj41]
links: []
created: 2026-11-07T22:09:38Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-bquq
tags: [ui-rules]
---
# The listening timeline reports choices to the controller that opened it

Rules: UI rule 1 (only controllers cause side effects). UI rule 3 (subscribe at the lowest level).

Breaks:
- lib/playback/timeline.dart, _ListeningTimelineState.build: a ListenableBuilder on the whole Playback. While a book plays, the visible list rebuilds on each 200 ms tick.
- lib/playback/timeline.dart, _choices: calls restoreHistory, restoreBookmark and editAudioBookmark, and pops the sheet.
- lib/playback/timeline.dart, _delete: confirms, then calls deleteHistory or deleteBookmark.

Target design:
openListeningTimeline is the controller side, as changeDownload is for downloads. It wires a ListeningTimeline leaf to Playback. The leaf gets the entries as a listenable that changes only when the records change (the records signal from boo-y6fb). It reports onGoBack(event), onGoTo(event), onGoToBookmark(bookmark), onRename(bookmark) and onDelete(entry). The controller side confirms a delete, closes the sheet before a jump, and names a bookmark through the shared bookmark editor from the player ticket. The open entry stays as ephemeral state in the leaf. Keep the signature of openListeningTimeline, because PlayerView and BookPage call it.

Owned files: lib/playback/timeline.dart and its tests.

## Acceptance Criteria

- A playing tick rebuilds no timeline row (rebuild counter).
- Delete reports onDelete(entry). The controller confirms, then deletes.
- Go back closes the sheet and restores the history action, as today.
- ListeningTimeline calls no Playback method that changes records or position (a fake that throws on those calls).

