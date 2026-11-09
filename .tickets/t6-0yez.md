---
id: t6-0yez
status: open
deps: []
links: []
created: 2026-11-09T17:35:49Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-b2ey
---
# Measure the open of a book with a kept admitted book on an emulator and on the Pixel 8

t7-rcyp keeps each downloaded book's admitted record, so a later open reads it instead of admitting the book. Its emulator measurement could not run: the Mac's disk had 5.1 GB free, and the Android 36 image needs 7.4 GB for an emulator's data partition. docs/research/epub-first-page-timing.md has host numbers only. Run tool/reader/open_benchmark.dart for the five books of boo-rw7u on a new emulator and on the Pixel 8, before (commit 6a20329) and after t7-rcyp. Report admission and the total to the first page, cold and warm, and the admitFull samples (the first open after a download).

## Acceptance Criteria

The research doc has emulator and Pixel 8 numbers before and after t7-rcyp for the five books.

