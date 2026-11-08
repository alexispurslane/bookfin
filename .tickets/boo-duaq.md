---
id: boo-duaq
status: in_progress
deps: []
links: []
created: 2026-11-08T15:33:33Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Show deck cards as blank glass cards until their page is drawn, with page margins inside

User request (2026-11-08) after boo-foo7: (1) a deck card shows blank until its own page image is drawn; drop the nearest-drawn-page fallback. (2) Cards use the app's glass card style (CoverGlass and the glass layers of docs/mockups/bookfin.html), so a blank card is an empty glass card and a drawn card is the page inside a glass frame. (3) The page inside a card needs inner padding like a page margin; today text runs close to the card edge and the last line is clipped (docs/screenshots/reader-deck.png). (4) Drawing an EPUB page must never block the Android main thread (which also runs Flutter's UI isolate) or the scrub gesture: no per-page work on that thread, including large JavascriptChannel messages; measure it.

