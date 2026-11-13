---
id: boo-hd47
status: in_progress
deps: []
links: []
created: 2026-11-12T23:41:01Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Compute the contents entries of each EPUB section once, not at each page turn

## Settled scope — 2026-11-13

The existing prepared section owns the facts derived from its DOM. Prepare the section's applicable contents locations and fallback heading once with that section, then use them when reporting a shown page. Keep URL resolution, heading traversal and contents-location derivation off the repeated page-report path. Reuse existing worker preparation and section lifetime/eviction paths; do not add a global cache, another source of chapter-title truth, or a general indexing framework. Full and partial preparation, excerpts, settings changes, eviction and reopen must retain coherent ownership.

Preserve current chapter-title semantics: package-relative paths and decoded fragments; entries without fragments; missing or malformed targets; CFI ordering; last equal-position entry wins; heading fallback; Chapter N fallback; 512-character limit. Use meaningful red-green behavior and work-count evidence for repeated page reports with many contents entries, not host timing thresholds or Android latency claims. Inspect actual consumers before deciding the smallest internal interface. The existing ownership model settles this work; report only a genuine product fork.

Owned scope: EPUB preparation/places/pager and narrow source wiring/tests, this ticket. Preserve boo-rcgf's paragraph-width ownership and active excerpt lifetime. Required Nix checks: focused regression/places/pager/preparation tests, reader and crossings suites, affected analysis/format, full Flutter suite. Concurrency two, one heavy command at a time. Implementation and direct fixes Astra xhigh; one fresh read-only Astra high reviewer, no second reviewer. No device, browser, coverage, mutations, push, PR or closure; parent owns integration and closure.

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: path confirmed, cost estimated. lib/reader/epub/pager.dart:761-777 and lib/reader/epub/places.dart:237-276. Each reported page turn resolves the URL of every contents entry in the book, walks the section DOM for a heading, and scans all text nodes with `indexOf`. A book with thousands of contents entries (a Bible, collected works) spends an estimated 2 to 10 ms for each turn on the UI isolate. lib/reader/epub/search.dart:232-253 already filters entries by section. Compute the entries and the heading once for each prepared section.
