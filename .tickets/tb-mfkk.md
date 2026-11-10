---
id: tb-mfkk
status: in_progress
deps: [tb-22fu]
links: []
created: 2026-11-10T02:33:42Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Select, copy, find and read word images in reflowed PDFs

W8 of docs/plans/pdf-word-image-reflow.md (The text under the images). Carets are characters of the reading text, through the text attachment. A point maps to a caret by its share of a piece, evenly over the piece's characters; highlights are the covered parts of target rectangles. Before a scanned page's text attaches, selection and highlights do nothing. Extract the selection event handling that the EPUB page (lib/reader/epub/selection.dart) and the word screen share into one selectable that takes four questions, or keep two and write why. Search hits open their screen. Screen readers read one node per paragraph. Expose the rectangles of a character range for read-aloud (t0-t799).

## Acceptance Criteria

Behavior tests, red first: a long press selects the word under the finger; a long press before the text attaches selects nothing; handles move by characters; copy gives the reading text of the selection; a piece with an empty range is never selected; a search hit opens the screen that holds it; a screen reader reads each paragraph's reading text. EPUB selection tests still pass.

## Notes

**2026-11-10T20:32:18Z**

Launched from integrated base 2ef6bfa with codex/gpt-6.1-sol reasoningEffort=xhigh. taskId: node:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-word-followup-20261110-tb-mfkk-1; childThreadId: thread:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-word-followup-20261110-tb-mfkk-1; clientRequestId: sol-xhigh-word-followup-20261110-tb-mfkk-1. Separate T3 worktree; lead implements, one fresh read-only Sol xhigh reviewer, lead fixes. Parent integrates/closes and owns hardening. No physical-device UI input. Launch state: running; branch pending report.
