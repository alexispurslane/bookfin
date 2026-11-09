---
id: t7-bbv1
status: open
deps: []
links: []
created: 2026-11-09T16:08:24Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Let a turn into the next section wait only for that section's prepare

Found in boo-rw7u (docs/research/epub-first-page-timing.md). When a page is shown, PageSource.show asks for the next section's first page and for the previous section's main run in the same microtask. _flush then prepares both sections in one worker call, and the call returns both prepared sections only when both are done. So a turn into the next section that comes before the call ends waits for the previous section's prepare too. On the emulator, a turn from the last page of Keats' section 3 into section 4, right after the page was shown, took 388 ms (median of 25), but section 4 alone prepares in 10 ms; section 2 (430,000 characters) is the previous section in the same call. In Standard Ebooks' Hamlet, the same turn into act 2 took 205 ms, and that act alone prepares in 49 ms. In ordinary novels the turn took 40 to 50 ms. A reader meets this only when a turn comes within about 0.15 to 0.4 s after the page is shown, for example right after opening at the last page of a chapter. The fix needs no pool of workers: the next section can get a worker call of its own, or the batch can return each section as it is done. One more worker call costs about 2 ms of spawn and 2 to 8 ms of warm-up in the new isolate (hyphenation patterns and first use) on another core.

## Acceptance Criteria

The turn of the open benchmark into Keats' section 4 and Hamlet's act 2 takes about as long as that section's own prepare and its first page, and the pages and saved places stay the same.


## Decisions (user, 2026-11-09)

This ticket now covers the whole order of prepare and layout work, not only the turn into the next section.

1. The UI waits only for the page that the reader opens or jumps to. Prepare that section and cut that exact page first (the anchored page), and show it.
2. Then lay out the shown section around that page: its neighbors and its main run.
3. Then two independent directions of work go outward from the shown section. One prepares and lays out the sections after it, in order to the right (S+1, S+2, ...). The other does the sections before it, in order to the left (S−1, S−2, ...). Each direction has its own worker, so neither waits for the other.
4. The work goes on, within the frame budget between frames, until every section of the book has its main run, so the whole book is laid out.
5. A jump starts the same order again from the page that the reader jumped to.
