---
id: boo-tam0
status: in_progress
deps: []
links: []
created: 2026-11-11T19:29:29Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Find how to make opening a book much faster

User request 2026-11-11: explore how to make opening books way faster. Benchmark sym-drawn4 (docs/marketing/epub-renderer/README.md, 'Rerun timed through each engine's drawing'): fresh open Bookfin 370 ms vs KOReader 118 ms (illustrated book 589 ms), cached reopen 47 ms vs 17 ms. Exploration only: profile where the time goes from tap to first drawn page for EPUB, MOBI and PDF, compare with KOReader's and others' approaches, and propose two designs with expected gains and costs. No production changes.


## Notes

**2026-11-11T19:59:59Z**

Research done in docs/plans/faster-book-open.md. Device medians (own host-GPU emulator bookfin-tam0, drawn page): fresh open 204 / 273 / 609 / 1,092 ms (prose, long, illustrated, large illustrated), MOBI 596 ms. Cached reopen 49 / 61 / 85 / 84 ms, MOBI 43 ms. Admission is 60 to 95 percent of a fresh open. Pure-Dart CRC-32 and SHA-256 of every file dominate the illustrated books. The parse, clean and serialize of every XHTML file dominate the text books. A cached reopen loses 9 to 16 ms waiting for page settings and 11 to 28 ms in a new prepare worker. A 568-page scanned PDF spends 1.5 s in pdfrx measuring every page at open. The plan lists ten quick wins, two designs and five questions for the user. Design A admits each book at the end of its download and draws a kept page first. Design B opens lazily, with only the first page's files. Scratch instrumentation and raw logs: branch scratch/boo-tam0-open-trace.

**2026-11-11T20:09:32Z**

Decisions recorded in the plan. Quick wins: boo-yjq6. Design A: boo-sy2d. Damaged chapters: t5-gk30.
