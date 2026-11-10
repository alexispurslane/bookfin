---
id: t6-chz6
status: open
deps: [boo-5fcg]
links: []
created: 2026-11-10T19:48:31Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fval
---
# Transform rotated PDF character boxes into the drawn page coordinates

pdfrx_engine 0.9.0 gives unrotated character boxes with rotated page dimensions.
A PDF page 600 by 400 points, rotated 90 degrees, can have visible text at x=440 while page.width is 400.
boo-5fcg disables text-layer geometry for rotated pages so that the printing-label filter cannot discard visible text.
Transform character geometry to the drawn page coordinates without changing extracted reading text, its digest, or saved character addresses.
Cover 90, 180 and 270 degree pages with synthetic native PDFs and prove both crops and word-image alignment.
