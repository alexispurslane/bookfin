---
id: boo-rw7u
status: in_progress
deps: []
links: []
created: 2026-11-09T15:30:53Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-b2ey
---
# Measure the time to a book's first page, and prepare chapters in parallel only if it pays

User request (2026-11-09). Text layout must stay on the root isolate (Flutter: 'UI actions are only available on root isolate', checked 2026-11-09), but prepare (parse, cascade, styled runs, hyphenation points) already runs in a worker isolate, one section after another. Step 1: measure where the time from tapping Read to the first drawn page goes on an Android emulator profile build, for a few real books (ordinary novel, a book with a big first section, a heavily styled Standard Ebooks book, a MOBI): publication load and admission, font loading, prepare of the first section and of its neighbors, the anchored layout, the first picture. Step 2: only if prepare is a large share of that time or of a turn into an unprepared section, prepare sections in parallel across a small pool of worker isolates (weigh each hop's fixed cost and copying the prepared section back). Report the numbers either way; if parallel prepare does not pay, record why and stop. Also report any other large share found (for example admission or font loading) as tickets.


## Notes

**2026-11-09T16:09:28Z**

Measured on an arm64 Android 36 emulator, profile build, tool/reader/open_benchmark.dart, five books, 5 cold and 25 warm runs each (docs/research/epub-first-page-timing.md). Admission is 59 to 93 percent of the time to the first drawn page (190 to 950 ms). Prepare of the shown section is 1 to 8 percent, and 33 percent only in Keats' 430,000-character section (328 ms). A first page and a jump each need one prepared section, so several workers cannot shorten them. A pool of workers that stay alive saves about 8 ms of warm-up for each ordinary section, but its results come back as copies (89 ms for Keats' section), so it is slower where prepare matters. The one real gain of parallel prepare is a turn right after a page is shown, which waits for the previous section in the same worker call (Keats 388 ms where 10 ms is enough); t7-bbv1 fixes that without a pool. Decision: parallel prepare was not built. New tickets: t7-rcyp (admission), t7-bbv1 (the batched turn), t7-49gt (very large sections).
