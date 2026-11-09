---
id: boo-rw7u
status: open
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

