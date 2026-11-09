---
id: boo-f8ke
status: in_progress
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


## Notes

**2026-11-09T01:27:18Z**

Cause: the front card's AnimatedSwitcher cross-faded the old page out and the new page in at the same time, each sliding 8% of the card width the opposite way. Mid-fade both texts showed at about half strength, offset sideways; the tc-1yif screenshot caught that. The glass and the paper were not the cause: the paper is opaque in both themes. Fix in ScrubDeck._card: a layoutBuilder keeps only the current child, so the old page leaves at once; the new page still fades and slides in from the way the thumb moved, over the empty glass. Tests: scrub_deck_test 'when the front card turns to another page, it never shows two pages at once...' and 'while the thumb passes several pages quickly...', both red before the fix (two RawImages on the front card). Device: own AVD bookfin-f8ke (deleted), fixture via adb reverse; screenshots docs/evidence/reader/native/06-scrub-deck*.png in night and cream, at rest and while dragging.
