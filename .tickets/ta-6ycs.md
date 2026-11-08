---
id: ta-6ycs
status: open
deps: []
links: []
created: 2026-11-08T16:25:48Z
type: feature
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Place reading places on the track of a sync choice

The Personal records page draws the places of a listening-place conflict as pins on a track of the whole book (lib/sync/choice.dart, BookTrack). A reading place has no known position in the whole book: an EPUB anchor holds a CFI and a quote, and a PDF anchor holds its page but not the page count. So a reading-place conflict shows only the two columns, unlike the 'Salt and Lantern' example in docs/mockups/personal-records-b.html. Found on 2026-11-08 while building boo-vtvp.

## Acceptance Criteria

A reading-place conflict shows both places on a track of the whole book when the reader knows the book's length; tests cover EPUB and PDF places.

