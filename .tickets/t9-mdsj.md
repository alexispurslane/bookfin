---
id: t9-mdsj
status: in_progress
deps: []
links: []
created: 2026-11-09T21:59:37Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-m27l
---
# One record model for places, moves and bookmarks


Design: docs/plans/reading-history.md, "The model". Order of work 2. No user decision needed. A refactor: no change of behavior and no change of stored data.

Build:

- `sealed class Place` in lib/catalog/model.dart. `AudioPosition` and `TextPosition` extend it.
- `HistoryEvent<P extends Place>` replaces `ListeningEvent`, and `HistoryAction` replaces `ListeningAction`. Add the kinds `link`, `search` and `open` now, with their timeline labels. If the user chooses design B of decision 2, add `close` too.
- `Bookmark<P extends Place>` replaces `AudioBookmark` and `TextBookmark`. `bookTitle` and `editionLabel` are optional. A reading bookmark that the reader creates or edits saves both from now on.
- `TimelineEntry`, `ActionEntry` and `BookmarkEntry` hold `HistoryEvent<Place>` and `Bookmark<Place>`.
- Rename `ListeningTimeline` to `HistoryTimeline` and `openListeningTimeline` to `openHistory`. Update every caller, the gallery and the tests.

## Acceptance Criteria

- Golden tests pin the JSON of a listening event, a listening bookmark and a reading bookmark as today's code writes them. The new code writes the same bytes and reads them back equal. Write these tests first, against today's code.
- A reading bookmark without `bookTitle` and `editionLabel` decodes and shows in the reader as today.
- A reading bookmark that the reader creates saves the book title and the edition label.
- Every existing test passes without a change of behavior.
