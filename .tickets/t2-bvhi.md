---
id: t2-bvhi
status: open
deps: []
links: []
created: 2026-11-10T16:53:00Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-fval
---
# Keep the faint edges of letters that lie just outside a scanned word's box in its word image

Found in te-qg8l (2026-11-10). On the Raven page, Tesseract's layout boxes are tight to the dark ink. Gray print at 0.5 to 0.8 of the paper's luminance lies 1 to 3 pixels outside some boxes (for example x 616-619 left of 'EDGAR', and rows 2007-2010 under 'BY', at 1600 px wide). A word image shows only its box, so these soft edges are cut. A probe that counts print below three quarters of the paper's luminance in text lines found 27 such marks on the Raven page, and none at the ink rule's own threshold of half the paper's luminance. Decide whether a word's image grows to hold the print that touches its box, within limits that keep word spaces and neighbor lines apart, and measure whether the cut edges are visible on the Pixel 8. te-qg8l joins only gaps that print bridges from word to word.

