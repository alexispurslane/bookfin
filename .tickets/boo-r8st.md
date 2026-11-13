---
id: boo-r8st
status: in_progress
deps: []
links: []
created: 2026-11-12T23:41:02Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Limit an EPUB note to its own content when its anchor is empty

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: plausible, it depends on the markup of the book. lib/reader/epub/places.dart:391-399 climbs from an empty note anchor to the nearest ancestor with visible text, which can be the whole notes block or the body. `pager.note` then lays that out on the UI isolate, and `run.pages.single` (lib/reader/epub/pager.dart:357) throws when the block is taller than the note height. Take the content up to the next anchor as the note and set a size limit.

## Parent read-only audit — 2026-11-13

At `27dc49fd`, noteOf in places.dart still climbs from an empty anchor to
the first ancestor containing visible text. An unmarked body containing
several empty anchors can therefore be selected as one note. Marked note
ancestors take priority, and that rule must be preserved. The existing
places_test.dart case only covers one empty anchor inside its own paragraph;
it does not cover adjacent notes sharing a body or container.

The survey's pager location and unscheduled-layout description are stale.
EpubPager.note now asks EpubPageSource.excerpt, which shares section
measurements and steps between event-loop turns. The fragment still uses
height 1e6 pixels, and takeExcerpt still reads run.pages.single. An oversized
fragment is thus a plausible remaining failure, not a reproduced result.
No test or implementation for this ticket ran during this audit.

ReaderScreen._followLink already follows the original destination when
pager.note returns null, retaining access to the full note in the book.
It catches ArgumentError and Exception, but not the StateError from a
multi-page single getter. Do not substitute a broad catch for bounded note
selection and owned excerpt cleanup. Existing layout scheduling, settings
invalidation, image disposal, backlink omission, copying and selection must
remain under their present owners.

Before implementation, settle how to represent a note range without changing
the admitted DOM's node identities or copying a fake subtree. The range must
exclude the next note and surrounding material, retain the simple paragraph
case and marked-note semantics, and preserve original locations. Size limits
need an explicit overflow behavior; existing null-to-navigation is an
available path, not a decision recorded by this audit. Useful callers and
tests: native-epub-reader.md's implemented note section, places_test.dart's
note group, pager_test.dart's note/backlink cases, page_source excerpt tests
and ReaderScreen._followLink. No delegate launched and no product choice
was settled here.

## Remaining user choice — 2026-11-13

The accepted design already gives normal notes a scrolling glass sheet and a
title-row Go to note action. The parent asked what happens only when a note
exceeds the bounded excerpt capacity: show its beginning with Go to note for
the rest, or navigate directly to the full note. The first option was recommended
to preserve the current reading page. No answer has arrived. Do not infer one.
The representation of an original-DOM range is an implementation responsibility,
not a product question. No implementation or delegate has started.

## User decision and settled scope — 2026-11-13

The user chose a limited preview for an exceptionally large note. Keep the
current reading page and the existing title-row Go to note action for the full
note. Normal notes keep their scrolling sheet. The pending-choice note above
is superseded. Make an omitted remainder understandable to the reader.

Select only the target note from the original admitted DOM. Preserve marked
note ancestors, simple paragraph notes and original node identities. Exclude
neighboring notes and unrelated text when an empty anchor shares a container.
Bound excerpt work and ownership so oversized notes cannot fail through a
single-page assumption. Preserve scheduled layout, cancellation, settings
invalidation, backlink omission, images, selection, copying and saved places.
The existing excerpt owner must release unfinished work and unreturned pages.
Do not clone a fake subtree or catch programming errors as a fallback.

Prove meaningful original behavior failures, then focused note/place/excerpt
and actual sheet tests, affected reader/crossing tests, the full suite at
concurrency at most two, analysis, formatting and complete-diff whitespace
checks through Nix. Preserve failures, skips and execution evidence. Exactly
one fresh read-only reviewer assesses correctness, fulfillment and design.
Parent owns integration, user acceptance, coverage, mutations and closure.
