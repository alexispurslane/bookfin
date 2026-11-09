---
id: boo-02sx
status: in_progress
deps: [t7-bbv1]
links: []
created: 2026-11-09T17:13:34Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-b2ey
---
# Estimate the time left in the book

Requested by the user on 2026-11-09. Show an estimate of the reading time left in the book and in the chapter. The reading speed comes from this reader's own page turns (pages or characters per minute, ignoring very short and very long pauses). The amount left comes from the whole-book page starts of t7-bbv1, or from visible characters before the book is laid out. Decide where the speed is stored and whether it is per book or per reader; it is derived data and must never put listening history or reading places at risk. Show nothing until the estimate has enough samples.


## Decision (user, 2026-11-09)

The bottom bar label adds the time left in the chapter, for example "Page 134 of 412 · 6 min left in chapter". The time left in the book shows in the contents sheet.

## Implementation (2026-11-09)

- `lib/reader/reading_speed.dart`: `ReadingSpeed` owns the speed. It is the median speed, in visible characters per minute, of the latest 40 counted pages in any book. It is one speed for the reader, so a new book shows an estimate from its first pages, and the window moves to the new book's speed in about 20 pages.
- A page counts when the person turned forward from it, it holds at least 250 visible characters, and its speed is from 100 to 4000 characters per minute. A faster page was flipped or skimmed. A slower page held a pause.
- The speed shows after 5 counted pages, and then changes after every 5 more. `roundEstimate` rounds the times: to the minute under 10 minutes, to 5 minutes under an hour, then to 10 minutes. So the label does not move on every page.
- The speed has its own store, `bookfin.reading-speed.v1` in the app preferences. The platform writes it atomically. A store that cannot be read gives no speed, and the next counted page replaces it. Places and history live in the record database, which the speed never touches.
- `BookMap.charactersLeft` counts the characters to the next chapter start and to the book's end. It estimates a section from its bytes until a main run counts its characters, as for a section that a kept page map seeded.
- The session's `timeLeft` and `timeLeftChanges` combine the place, the map and the speed. Only the label and the contents sheet line subscribe.
- PDFs show no time left (te-hzt6). Time in the background still counts toward a page (te-d6jt).
- Evidence: `docs/evidence/reader/time-left/`.
