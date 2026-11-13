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

## Parent launch record — 2026-11-13

- Original base: `e23662daf2e4e9b737aee4366c418f0ec5591145`.
- Task ID: `node:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-boo-r8st-astra-20261113-1`.
- Child thread ID: `thread:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-boo-r8st-astra-20261113-1`.
- Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-boo-r8st-astra-20261113-1>.
- Client request ID: `bookfin-boo-r8st-astra-20261113-1`.
- Branch at launch inspection: `t3/bounded-note-previews`.
- Worktree: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-c0996feb`.
- Lead: codex/gpt-6-astra, xhigh. One fresh read-only reviewer: the same model, high.
- Stages: build, review, fix if needed, then parent integration and acceptance.
- Launch accepted. No implementation result or acceptance is claimed.


## Implementation evidence — 2026-11-13

Lead checkout: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-c0996feb`,
branch `t3/bounded-note-previews` (renamed from `t3/c0996feb` at the base,
as confirmed by the branch reflog). It began clean at original base
`e23662daf2e4e9b737aee4366c418f0ec5591145`; no prerequisite diff was pending.

The original failures are retained in
`/tmp/bookfin-boo-r8st-evidence/01-original-red.log`: surrounding and next-note
text entered two previews, and 120 short paragraphs with large authored line
spacing raised `StateError: Too many elements`. This is a bounded controlled
reproduction, not a soak or performance measurement.

Whole elements and empty-anchor notes now use one original-document selection.
Actual note-reference destinations distinguish next notes from internal empty
anchors. Marked ancestors retain priority. Excerpt preparation keeps the DOM
and unchanged flow identities, including shared table measurements. Excerpt
layout stops at its first page with 12,000 logical pixels of capacity, releases
unfinished work and surplus pages, and reports omitted content through the
page's existing last-page flag. The shared glass sheet retains its title-row
Go to note and shows a short notice for a limited preview. The reading place
and saved history stay unchanged until explicit navigation.

Additional regressions reproduced and corrected during implementation include
clipping/omission inside table cells, truncation at an internal empty anchor,
continuation after a backlink, and cancellation during image decoding.
Compilation mistakes and one test-helper misuse were recorded as development
failures, not counted as meaningful red evidence. All command logs and their
results are indexed in `docs/evidence/boo-r8st/commands.json`.

The final focused set passed 58 tests. The final affected reader and Crossings
suites passed 1,733 tests with 21 declared skips. The final full run passed
3,711 tests with 27 declared skips. Earlier full and affected runs, including
all development failures, remain in the command manifest. The sole review
is pending. Affected analysis has no issues; all 15 changed Dart files pass
format verification. The review uses client request
`bookfin-boo-r8st-review-20261113-1`, Codex `gpt-6-astra`, high reasoning,
shared isolation, async mode, and read-only review role. Parent retains integration,
acceptance, coverage, mutation testing and closure. No device/browser work,
credentials, other-ticket changes, PR, push, merge or ticket closure was done.
The unrelated t5-rplx cause remains uninvestigated here; tf-il7u is unchanged.
