---
id: boo-r8st
status: open
deps: []
links: []
created: 2026-11-12T23:41:02Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Limit an EPUB note to its own content when its anchor is empty

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: plausible, it depends on the markup of the book. lib/reader/epub/places.dart:391-399 climbs from an empty note anchor to the nearest ancestor with visible text, which can be the whole notes block or the body. `pager.note` then lays that out on the UI isolate, and `run.pages.single` (lib/reader/epub/pager.dart:357) throws when the block is taller than the note height. Take the content up to the next anchor as the note and set a size limit.

