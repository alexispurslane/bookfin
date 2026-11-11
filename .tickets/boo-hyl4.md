---
id: boo-hyl4
status: in_progress
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

**2026-11-11T15:31:35Z**

Design written in docs/plans/history-choice.md (2026-11-11). Cause of 'not quite align': (1) 'Go back' names the before place, so on 'Moved back 40 s' it goes 40 s ahead in the book; (2) the row shows only the after place; (3) the move label rounds the exact difference while the place texts round down, so 'Moved back 41 s' sits over 1:02:55 and 1:02:15 (fix: tc-p3j8); (4) the choices are a Wrap that starts 6 points right of the row text, so Delete drops to its own line or moves, and quote labels wrap inside a button. Two designs: A, one place per entry (where you were; one Go to); B, a route per move (Before and After tiles). Mockups under ~/.cache/bookfin/previews/boo-hyl4/. Waiting for the user's answers to the questions in the doc. Side finding: tc-butt (Opened entries never name the other device).
