---
id: boo-rcgf
status: in_progress
deps: []
links: []
created: 2026-11-12T23:41:01Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Own EPUB paragraph segment measures by content width, not in a global table

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed by static trace, not executed. lib/reader/epub/layout.dart:2147-2224. `_found` is a static Expando keyed by the paragraph object, with no width in the key. `pager.note` (lib/reader/epub/pager.dart:310-335) lays out a note excerpt at the sheet width, and `without(item)` (lib/reader/epub/prepare.dart:354-366) shares the later paragraph objects with the page. A note whose second or later paragraph exceeds about 1,024 code units overwrites the segment starts of that paragraph. A later page-width run that starts inside the paragraph then cuts a page at the wrong text (skipped or repeated lines). In a seeded section `agrees()` fails and the kept page map is deleted. No test covers a note with a long paragraph. Reproduce it first with a test. Then make the measures a value that the owner of the run holds, keyed by item and width, and lay a note out through the page source.


## Astra implementation scope

Start from the integrated catalog migration and PDF frame fixes on main. The current integrated catalog suite is running; the previous main baseline was 3,231 passes and 25 skips, and the catalog branch reported 3,252 passes and 25 skips. Build and direct fixes use codex/gpt-6-astra, reasoningEffort xhigh. One fresh read-only reviewer uses the same model with reasoningEffort high. No other children. The parent integrates and closes.

Reproduce cross-width contamination through a long note paragraph shared with a page and a later page-width run starting inside that paragraph. Use one explicitly owned measurement model for layout, position search, kept measures, and notes, keyed by the actual paragraph and content width. Preserve resumable work budgets, correct kept-map validation/rejection, and place continuity. Route note layout through its existing page-source ownership. No new product choice or wholesale EPUB engine redesign is intended.

Required checks include meaningful failing regression(s), all EPUB tests and crossing tests, affected analysis/format, and the complete Flutter suite with concurrency at most two. Builds and tests use nix develop, one heavy command at a time. Leave coverage, mutations, device acceptance, integration and ticket closure to the parent.

## Delegated task

Original base: adb8c2bfc190fd7c6db9de166deecbf1baa6cba8.
Client request ID: bookfin-boo-rcgf-astra-20261113-1
Task ID: node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-rcgf-astra-20261113-1
Child thread ID: thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-rcgf-astra-20261113-1
Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-rcgf-astra-20261113-1>
Launch returned running on codex/gpt-6-astra with reasoningEffort xhigh. Stage and branch not yet reported. Completion delivery is automatic.
