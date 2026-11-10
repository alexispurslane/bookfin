---
id: tb-zx7r
status: in_progress
deps: [tb-22fu]
links: [te-rtok]
created: 2026-11-10T12:48:24Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Cut the PDF text view into screens of whole lines

W6b of docs/plans/pdf-word-image-reflow.md (Screens and turns, decision 2 of 2026-11-10). The text view stops being one scroll column. It lays out the reading text with its TextPainter as today, gives the line metrics to cutScreens (from tb-0mex), and draws one screen as the part of the painter from the screen's first line top to the next screen's first line top, with no scroll controller. A swipe shows the next or previous screen, past the last screen it shows the next source page's first screen, and back from the first screen the previous page's last screen. A vertical drag does nothing. The place of a screen is the first character of its first line. A text size or width change cuts the screens again and shows the screen that holds the shown place.

## Acceptance Criteria

Behavior tests, red first: no text view screen cuts a line or starts with a paragraph gap; a swipe shows the next screen and passes between source pages at their ends in both directions; a vertical drag changes nothing; the place of a screen is its first line's first character and reopening at it shows the same screen start; a size step keeps the shown place on screen; a place saved in the word view opens on the text view screen that holds it. Existing PDF reflow tests that scrolled are rewritten to turn screens, and the move by 85 percent of the viewport is gone.


## Notes

**2026-11-10T20:32:18Z**

Launched from integrated base 2ef6bfa with codex/gpt-6.1-sol reasoningEffort=xhigh. taskId: node:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-word-followup-20261110-tb-zx7r-1; childThreadId: thread:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-word-followup-20261110-tb-zx7r-1; clientRequestId: sol-xhigh-word-followup-20261110-tb-zx7r-1. Separate T3 worktree; lead implements, one fresh read-only Sol xhigh reviewer, lead fixes. Parent integrates/closes and owns hardening. No physical-device UI input. Launch state: running; branch pending report.
