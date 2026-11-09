---
id: tc-fz4n
status: in_progress
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


## Notes

**2026-11-09T01:29:44Z**

Done in this branch. lib/reader/epub/semantics.dart: pageBlocks(page) gives the shown page's text blocks and block images in strip order. A block is one paragraph flow item's lines on the page (a hanging first line joins its paragraph; table cells are blocks cell by cell). Its text is the DOM character of each shown code unit, each once, so layout's U+2010 hyphens, inserted soft hyphens and word joiners never appear; the book's own soft hyphens are dropped; raised text reads its DOM text in place. A block splits into spans at links and inline images. viewport.dart: the page's render object is the page semantics node (scroll left: onTurn(true), scroll right: onTurn(false)); it marks semantics dirty when pager.shown changes, so a turn updates the nodes without a rebuild, and it keeps the same nodes while the same page is shown (the picture with decoded images). A one-span block is one node; a block of several spans holds one node per span. A link span's tap taps the page at the link, so it runs the same linkAt and onLink as a finger. The RawGestureDetector is excluded from semantics: its default actions tapped the page corner and scrolled nowhere. layout.dart gained two read-only members: LaidPage.dom and TextMap.nodeAt. Images without alt text are labeled Image, as the ticket says, including alt="". Device: own AVD bookfin-tcfz4n (deleted), synthetic server, agent-device accessibility tree; evidence in docs/evidence/reader/native/semantics/. The TalkBack check waits for t2-u76g: agent-device 0.21.31 still suppresses other accessibility services. New tickets: tc-u5z2, tc-kcbw.
