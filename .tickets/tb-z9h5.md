---
id: tb-z9h5
status: open
deps: [tb-t8rh]
links: []
created: 2026-11-10T12:53:21Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Find running headers, folios and each PDF page's content box in the page analysis

T1 of docs/plans/pdf-word-image-reflow.md (Trimmed margins: Content boxes, Running headers and folios). Extend analyzePage: mark the lines near the top and bottom edges that match the book's header and folio templates, and give the page's content box in page units: the union of its words, regions and uncovered ink, without marked lines. Write the template finder over a set of analyzed pages: a text signature (lowercase, white space joined, digits as #) that repeats at the same place on at least 3 pages within 20 source pages; a folio whose number minus the source page number stays the same on at least 3 pages; on scanned pages without text, an edge line whose place and size repeat on at least 30 percent of the body pages of its side. Only text lines can be headers; regions and footnotes never are.

## Acceptance Criteria

Behavior tests, red first, on a fixture book of at least 12 pages made with Typst (running header with the chapter title, folios at the outer bottom corner, a page with footnotes, a chapter start without a header, a figure near the bottom, a wide table) and on a scanned fixture sequence: headers and folios are marked on every page that has them; a chapter title at the top of a chapter start is not marked; footnotes and figures stay in the content box; the content box holds every word, region and uncovered ink that is not marked. Marking reads no text on scanned pages without text. Runs in a hop.


## Notes

**2026-11-10T14:59:40Z**

From tb-t8rh: the Raven page's analysis has a region for the scan's dark bottom edge (the full page width, 14 pixels tall at 1600 wide) and one for the pencil page number in the top margin, both picture kind, and the folio '1' as an ink region. A content box that is the union of all regions reaches the page's bottom edge. The Raven picture block of the layout pass also holds the title 'The Raven'.

**2026-11-10T15:03:43Z**

From tb-t8rh: the Raven scan's dark bottom edge and its pencil page number become picture regions, so a content box of all regions reaches the page's bottom. Exclude scan-edge regions (touching the page edge, very wide and thin) from the content box.
