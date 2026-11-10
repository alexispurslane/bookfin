---
id: tb-fi98
status: in_progress
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

**2026-11-10T21:09:03Z**

Implemented whole drop caps in the existing column model. Oversized opening words (including Raven's whole ONCE image) and ink regions share paragraph floating, at most three neighboring short lines, full width below the cap, and existing screen keep marks/band plans. No reading text, digest, attachment, page analysis, crop, viewport, settings, or record-storage code changes. Added public CC0 Typst/PDF opening-letter fixture and ten domain behavior tests. Red evidence: /tmp/bookfin-tb-fi98/red.log (four valid missing-behavior failures; initial OCR spelling assumption corrected), raven-red.log (expected two neighboring lines, got one), fit-red.log (a taller neighboring word split screens), full-test.log (ordinary ink anchored too early; expected region after piece 28, got piece 10). All fixed. Initial analysis found an unnecessary null assertion, unused import, and missing braces; fixed. Final Nix checks: dart format --output=none --set-exit-if-changed lib test tool integration_test: 395 files, zero changed; flutter analyze lib test integration_test: no issues; focused drop-cap tests: 10 passed; flutter test --concurrency=2 --reporter expanded: 2570 passed, 21 skipped, zero failures (4:05). Logs: /tmp/bookfin-tb-fi98/final-{format,analyze,focused,full-test}.log. Native code unchanged, so native OCR script not required. Flutter startup prints missing iPhone SDK notices; required host checks still pass. No devices operated, no coverage/mutation jobs. Independent review pending; ticket remains in progress for parent integration.
