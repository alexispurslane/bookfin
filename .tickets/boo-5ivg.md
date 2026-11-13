---
id: boo-5ivg
status: in_progress
deps: []
links: []
created: 2026-11-12T23:41:02Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Decode the admitted EPUB record off the UI isolate at reopen

## Current-path audit and settled scope — 2026-11-13

Parent inspection at 2aab2d8b finds that AdmittedBooks.load already calls read inside Isolate.run, including Publication.decode, and returns the publication through worker exit. EPUB and MOBI production open paths use load. Other direct read callers document worker-only use for speech/search. The survey may therefore be superseded by integrated boo-yjq6/boo-sy2d work. Audit every real production reopen caller before changing code; do not build a second offload or speculative abstraction for a stale finding.

Required result: admitted-record header decode, validation, text-resource splitting and associated copies run outside the UI isolate, within the existing owned read/worker operation. Preserve immutable resource bytes, lazy binary ranges, digest/policy/revision checks, damaged-record retention and re-admission, download holds, pending record writes, EPUB/MOBI behavior, and returned publication semantics. If current code already satisfies the requirement, provide source provenance and meaningful existing or added boundary proof, and make no production change. If a real caller violates it, reproduce that path before the smallest fix through the same owner.

Verification must show the production reopen path uses worker execution and retains publication facts; use real saved records and controlled boundary evidence, not a wall-clock threshold or a test of an unused helper. Run admitted-books/publication/platform/MOBI and affected download/speech/reader checks, affected analysis/format, and the full Flutter suite through Nix at concurrency two, one heavy command at a time. No Android speed claims. Exactly one fresh read-only Astra high reviewer; implementation/direct fixes Astra xhigh. No devices, browser, coverage, mutations, push, PR, merge or closure. Parent integrates and closes. Avoid EPUB preparation/places/pager work owned by boo-hd47.

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed on the UI isolate, size estimated. lib/reader/epub/publication.dart:243-268, called from lib/reader/admitted_books.dart:280. Each reopen decodes the JSON header of the record (the text of every style sheet, the contents list, the image sizes) and copies every text file, 2 to 10 MB, on the UI isolate while the kept page already accepts taps. Do the decode and the split in the worker hop that reads the record, and return the bytes through `Isolate.exit`. Related: t6-0yez (measurement), t0-r8ii.

## Launch — 2026-11-13

Astra xhigh lead launched from e72d2335b1197080464e2381b923b9b310429da2; running, stage uncertain. One fresh read-only Astra high reviewer authorized. Audit existing production worker ownership before deciding whether implementation is needed.

- clientRequestId: bookfin-boo-5ivg-astra-20261113-1
- taskId: node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-5ivg-astra-20261113-1
- childThreadId: thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-5ivg-astra-20261113-1
- Link: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-5ivg-astra-20261113-1>
