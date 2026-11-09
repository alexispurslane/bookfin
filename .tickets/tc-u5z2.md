---
id: tc-u5z2
status: open
deps: []
links: []
created: 2026-11-09T01:29:43Z
type: feature
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Read the numbers of ordered lists on a native page

Found in tc-fz4n. A screen reader reads each text block from the DOM (lib/reader/epub/semantics.dart). A list marker such as '1.' is generated content (MarkerDecoration), not DOM text, so the reader never hears the number of an ordered list item. Decide whether the marker text goes before the first span of its item's block, and add a semantics test.


## Notes

**2026-11-09T01:35:42Z**

Orchestrator, 2026-11-08: also skip a decorative image. An image with alt="" gets no semantics node, as HTML and screen readers expect; an image with no alt attribute keeps the label 'Image'.
