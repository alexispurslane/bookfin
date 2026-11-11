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

