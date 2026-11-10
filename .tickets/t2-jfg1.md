---
id: t2-jfg1
status: open
deps: []
links: []
created: 2026-11-10T14:01:51Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fval
---
# Add a scanned PDF fixture with a footnote mark, a line-end hyphen and an indented paragraph

Found in tb-jidt (2026-11-10). The design's scanned fixture should have italics, a footnote mark, a line-end hyphen, an indented paragraph and a figure with a caption. tb-jidt recorded the layout record and hOCR of the Raven page that tb-t0ea used (raven-raster-only.pdf): an engraving, a caption, a byline and three lines of verse, with no footnote mark, hyphen or indent. The page analysis (tb-t8rh, hyphens from pixels) and the column layout (tb-0mex, raised marks, indents) need a public-domain scan with those features. Record its layout and hOCR with tool/reader/ocr_layout_device_test.py --record, as test/reader/fixtures/reflow/README.md says.

## Acceptance Criteria

A public-domain scanned page with a footnote mark, a line-end hyphen and an indented paragraph, with its layout record and hOCR recorded on an emulator, its source and license in the fixtures README, and the device fixture test covering it.

