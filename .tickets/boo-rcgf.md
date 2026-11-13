---
id: boo-rcgf
status: open
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

