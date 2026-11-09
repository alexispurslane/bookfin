---
id: tc-kcbw
status: open
deps: []
links: []
created: 2026-11-09T01:29:44Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Follow a link around a block image

Found in tc-fz4n. EpubPager.linkAt only reads paragraphs, so a tap on a block image inside a[href] (display: block) follows no link, and the image's semantics node has no tap action. An inline image in a link works. Make linkAt find the link of a block image slice, then give the image node the link's tap.

