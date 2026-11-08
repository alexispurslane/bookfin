---
id: tc-fz4n
status: open
deps: [tc-1yif]
links: []
created: 2026-11-08T19:23:12Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-b2ey
---
# Read native pages with TalkBack and other screen readers

Goal: assistive technology reads the text of the shown page in order, follows links, reads image descriptions and turns pages.

Design section: "Coverage beyond the trial / Accessibility".

Files: lib/reader/epub/viewport.dart, lib/reader/epub/semantics.dart (new), test/reader/epub/semantics_test.dart.

Rules:
- One semantics node per text block on the page, in strip order. Its label is the DOM text of the block's lines on this page, without soft hyphens.
- h1 to h6 blocks are headers. Each link is its own node whose tap calls onLink. Each image is a node labeled with its alt text. An image without alt text is labeled 'Image'.
- The page node has scroll left and scroll right actions that call onTurn.
- The semantics follow the shown page and change after each turn.

## Design

docs/plans/native-epub-reader.md (epic boo-b2ey). Read the sections named in the description. The design decides the owners, interfaces and order. Ask the orchestrator before changing them.

## Acceptance Criteria

- Semantics tests: a page's nodes hold its text in order, with nothing from other pages and no soft hyphens. Headings are headers. A link node's tap calls onLink. An image node has its alt text. A scroll action turns the page.
- After a turn, the nodes hold the new page's text.
- At text scale 2.0 the page lays out again and the nodes still match it.
- If t2-u76g allows it, a TalkBack device check passes. Otherwise the ticket records that the check waits for t2-u76g.

