---
id: boo-hyl4
status: closed
deps: []
links: [tc-butt, tc-p3j8]
created: 2026-11-11T15:11:08Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Make clear whether a history entry goes to the place before or after its move

User report 2026-11-11: a history entry offers two buttons, 'Go back to <before>' and 'Go to <after>' (lib/playback/timeline.dart around line 481). The labels are not clear, they can fail to line up with their entry, and two buttons feel awkward. Investigate and propose two designs, ideally one that unifies the choice. Design and report only; implementation follows the user's choice.


## Notes

**2026-11-11T15:11:48Z**

Design agent started (Claude Opus 5.5 xhigh, worktree, design only): clientRequestId opus-xhigh-boo-hyl4-history-choice-20261111-1. Output: docs/plans/history-choice.md and mockups in ~/.cache/bookfin/previews/boo-hyl4/.

**2026-11-11T15:31:35Z**

Design written in docs/plans/history-choice.md (2026-11-11). Cause of 'not quite align': (1) 'Go back' names the before place, so on 'Moved back 40 s' it goes 40 s ahead in the book; (2) the row shows only the after place; (3) the move label rounds the exact difference while the place texts round down, so 'Moved back 41 s' sits over 1:02:55 and 1:02:15 (fix: tc-p3j8); (4) the choices are a Wrap that starts 6 points right of the row text, so Delete drops to its own line or moves, and quote labels wrap inside a button. Two designs: A, one place per entry (where you were; one Go to); B, a route per move (Before and After tiles). Mockups under ~/.cache/bookfin/previews/boo-hyl4/. Waiting for the user's answers to the questions in the doc. Side finding: tc-butt (Opened entries never name the other device).

**2026-11-11T15:40:09Z**

User decision 2026-11-11: design B (a route per move), Before and After tiles of equal size. Implementation delegated with tc-p3j8 and tc-butt.

**2026-11-11T15:54:14Z**

Built design B in lib/playback/timeline.dart. A closed row of a move shows '→ <after place>'. An open move shows two tiles of one size, Before (onGoBefore, renamed from onGoBack) and After (onGoTo), across the row from the time column to Delete. An entry has two ends when samePlace(before, after) is false; other entries and bookmarks show one 'Go to' tile. Delete replaces the place text at the row's end; a bookmark's Name/Rename is a pencil icon before it. Tile lines never wrap. _end() describes every tile's place, for boo-z3is. Tests: test/playback/timeline_route_test.dart; old tests now tap tiles. Screenshots: ~/.cache/bookfin/previews/boo-hyl4/built/. Details in docs/plans/history-choice.md, 'Built'.

**2026-11-11T16:09:01Z**

Review (reviewer agent, 2026-11-11) of fd2d5836 resolved: (C1/D1) Played, Interrupted and Finished go from one position sample to the next, so their places can differ by milliseconds; the two-end rule is now one predicate HistoryEvent.moved = changesPosition && !samePlace. (C2) a seek within one shown second reads as its verb alone, not 'Moved ahead 0 s'. (C3/D2/T2) tiles always show chapter and quote; the quote line shows more of a quote place than the place text. (D3) AlongAudio documents that it is the time that PlaceWords.short shows. (D4) one glowAccent(theme) in foundation/theme.dart replaces five copies. (T3) stale doc lines and test names. Open for the user: Delete keeps a 48-point target, so an open row is taller than in the mockup; 'Went back in history' still uses 'back' in the time sense.

**2026-11-11T16:20:41Z**

Design B merged to main (t3/48870466, ae3b1e63); format, analyze lib test and 2669 tests pass on merged main. Follow-up in progress: swipe to delete and an open row of normal height, after user feedback that the open row's highlight was too big.

**2026-11-11T16:38:53Z**

Follow-up to user feedback (the open row's highlight was too tall, about 56 points against 29, and crowded the tiles): the open row now keeps the closed row's height and content. Delete is a swipe toward the start of any row (end-to-start only), on the error color, and the row springs back because the sheet still confirms. Each row has a Delete accessibility action. Name or Rename is a pencil tile at the right end of a bookmark's Go to line, as tall as the tile and at least 48 points. Screenshots: ~/.cache/bookfin/previews/boo-hyl4/built2/.
