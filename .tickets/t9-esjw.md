---
id: t9-esjw
status: in_progress
deps: [t7-bbv1]
links: []
created: 2026-11-09T18:24:43Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-b2ey
---
# Make the first text size press move a fixed-size book's text in the pressed direction

Found during boo-0ari on 2026-11-09. Before the first press of a text size button, a book that fixes its body text keeps its own size, for example 16 pixels (12 pt), while the reader's stored size is 20. The first press switches the reader to sizing the book's main text, from the stored size: Smaller gives 18 pixels and Larger gives 22. So the first Smaller press makes such a book's text larger. Every later press moves in the pressed direction. Books whose body text follows the reader's size (all 90 corpus books) are not affected. This needs a user decision. Option A: keep it. The first press is the moment the reader takes over, and the size shown in the settings sheet becomes true. Option B: step the first press from the open book's shown main text size, which needs the pager to report that size to the session.


## Decision (orchestrator, 2026-11-09)

Option B. boo-0ari already required that each press moves the text in the pressed direction. The first press steps from the main text size that the open book shows.

## Implementation notes (2026-11-09)

- The size buttons call `ReaderSession.stepFontSize(larger:)`. The session owns where a step starts. Once `sizesMainText` is on, it starts from `fontSize`. Before that, it starts from the main text size that the open book shows, in the reader's pixels before the system text scale: `fontSize` times `EpubPager.shownMainTextRatio()`.
- `shownMainTextRatio` is the shown page's main text size over the text size that the page was laid out for. The page source measures it in a worker (`PageSource.shownMainText`, `shownMainTextSize` in prepare.dart), on the same three sections as the book's main text size. A ratio, not a size in pixels, keeps the system text scale out of the session.
- The step is rounded to a whole pixel and clamped to 14 to 40. A step that does not move the text the way that it names does nothing: Smaller on a book that shows its text at 12 pixels keeps the book's own design.
- Steps run one after another, so two quick presses take two steps.
- Books whose text follows the reader's size step as before (20 to 18 or 22). A book whose text is 0.9 em (Leaves of Grass) now steps from 18 to 16. Before, its first Smaller press gave 18 and did not change the text.
- Follow-up: td-htsj (the settings sheet shows 20 until the first press).
