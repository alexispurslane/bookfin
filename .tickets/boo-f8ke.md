---
id: boo-f8ke
status: open
deps: []
links: []
created: 2026-11-09T01:01:26Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-b2ey
---
# The scrub deck's center card shows the text of a second page through it

Seen in docs/evidence/reader/native/06-scrub-deck.png (tc-1yif, Android emulator, night theme): the center card of the scrub deck shows two pages of text on top of each other ('Most years, the last column was empty...' and the heading 'Three. What the Orchard Remembers' with its paragraphs). Find the cause first: either the glass card is translucent so the neighbor card or the page behind shows through, or the deck cross-fades between two previews and the screenshot caught the middle of the fade, or two pictures are drawn in one card. The center card must show exactly one page, readable at rest; a transition, if any, must not leave two texts readable at once.

