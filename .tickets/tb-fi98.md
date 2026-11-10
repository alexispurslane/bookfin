---
id: tb-fi98
status: open
deps: [tb-22fu]
links: []
created: 2026-11-10T02:33:42Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Float drop caps at the start of reflowed PDF paragraphs

W9 of docs/plans/pdf-word-image-reflow.md (Regions, drop caps). A drop cap is an ink region at a paragraph start, more than 1.8 body line heights tall, whose right edge touches the first word. It keeps the page's scale and floats at the paragraph start, and the paragraph's first lines (at most 3) get shorter beside it.

## Acceptance Criteria

Behavior tests, red first, on a fixture page with a drop cap (add one to the scanned or Typst fixtures): the drop cap shows whole at the paragraph start; the lines beside it are shorter and the line after it is full width; the paragraph's reading text and places do not change.


## Notes

**2026-11-10T14:59:40Z**

From tb-t8rh: on the Raven page, the drop cap O of 'ONCE' lies inside the layout word of its line (that line is 64 pixels tall at 1600 wide, the others 33). It is not a separate ink region, so a drop cap can come as an oversized first word of a line, not only as a region.

**2026-11-10T15:03:43Z**

From tb-t8rh: the Raven drop cap sits inside the first word's box, not in a region of its own.
