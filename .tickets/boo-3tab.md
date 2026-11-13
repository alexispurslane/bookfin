---
id: boo-3tab
status: open
deps: []
links: []
created: 2026-11-12T23:41:01Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Make the EPUB image budget bound the decoded images that are alive

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: mechanism confirmed, size estimated. lib/reader/epub/page_source.dart:544-548 and 1733-1747. The trim holds `_imageBytes` at or below 32 MiB, but each cached page picture (up to 24 pages) keeps its own native reference to the images it draws. `image.dispose()` releases only the handle of the cache. An illustrated book with a full-page image on each page can retain about 240 MB while the invariant check passes. `pager.note` uses a second decode path with no cache and no budget (lib/reader/epub/paint.dart:178-216). Make one image owner for pages and notes. It counts an image as live while a cached picture draws it, or it evicts pictures instead of bare handles.

