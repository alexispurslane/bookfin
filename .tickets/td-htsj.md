---
id: td-htsj
status: open
deps: []
links: []
created: 2026-11-09T19:57:47Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Show the size that the open book shows in the reading settings before the first size press

Found in t9-esjw on 2026-11-09. Before the first press of a text size button, the reading settings sheet shows the stored text size, 20, while a book that fixes its body text shows its own size, for example 16 pixels. The first press steps from the shown size (ReaderSession.stepFontSize), so Smaller on such a book shows 14 next: the label jumps from 20 to 14. The label could show the main text size that the open book shows (EpubPager.shownMainTextRatio times ReaderSession.fontSize), which needs a measurement in a worker when the sheet opens. Also, a book that shows its text at 14 pixels or less keeps an enabled Smaller button that does nothing.

