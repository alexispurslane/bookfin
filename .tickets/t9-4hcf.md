---
id: t9-4hcf
status: closed
deps: [t9-k6kd]
links: []
created: 2026-11-11T15:44:45Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-z3is
---
# Go to a landing as a mapped move in the open edition's own track, with Undo

Step 6 of design A in docs/plans/cross-edition-places.md. HistoryEvent gets optional counterpartOf and matchedBy (no migration, JSON unchanged for other moves). ReaderSession.goToLanding and Playback.goToLanding go to a landing as a move of the choice's kind. Data-safety tests: a refused landing changes no record; a mapped jump writes no record of the other medium; Undo returns to the exact place before the jump; a kill during the save keeps the old place or the new place with its move.


## Notes

**2026-11-11T16:18:08Z**

HistoryEvent has optional counterpartOf (a Place of the other medium, decoded by its keys through decodeAnyPlace) and matchedBy (MatchedBy, moved into lib/playback/records.dart; an unknown name reads as null). Other moves keep their JSON. Playback.goToLanding(AudioLanding, kind) seeks the open edition through _seekPosition, and ReaderSession.goToLanding(TextLanding, kind) seeks the open book through _jump and navigator.seek; each records a move of the choice's kind in its own track, with the counterpart, which becomes the Undo offer. A landing outside the open edition, or in another revision of the open ebook, moves nothing and completes with false. Tests: test/playback/mapped_moves_test.dart (record format, the player) and the group 'a mapped move' in test/reader/reading_moves_test.dart (the real pager): the landing shows as a move with Undo; Undo returns to the exact place before the jump; the move and the new resume save in one change set (one store transaction, so a kill keeps both or neither); no record of the other medium is saved; a bookmark choice copies no bookmark; a refused landing moves and saves nothing. Check: dart format, flutter analyze lib test, flutter test: 2710 passed, 21 skipped.

**2026-11-11T17:47:01Z**

Review fix after step 7 (Q7): goToLanding and _restorePosition share one private step, _moveOpen, which seeks as a move and plays on.
