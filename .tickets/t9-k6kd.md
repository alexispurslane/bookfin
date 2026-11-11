---
id: t9-k6kd
status: in_progress
deps: [t9-4ey6]
links: []
created: 2026-11-11T15:44:45Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-z3is
---
# Find the landing of a place of the other edition through Crossings

Step 5 of design A in docs/plans/cross-edition-places.md. Crossings is an app-wide data source. It keeps text outlines in a JSON cache keyed by edition id and revision (atomic write), keeps alignments, and gives landing(place, into: openEdition). It writes no personal record. checkInvariants() checks the four documented invariants on demand.


## Notes

**2026-11-11T16:17:59Z**

Crossings (lib/crossings/crossings.dart) is the app-wide owner of landings. landing(place, from:, into:) waits for the alignment; landingNow gives the landing when the pair is aligned, else starts the work, and changes notifies when it arrives. Results: TextLanding (a BookPlace in the ebook's spine), AudioLanding (an AudioPosition in the file that holds it), or NoLanding with a Refusal (noChapters, fewMatches, partCovered, unmeasured, outsideMatches, noOutline). Text outlines come from memory, then OutlineStore (DiskOutlines: one file per key under bookfin-outlines beside the media storage, written to a partial file and renamed), then a measurement of the download, keyed by edition, file revision and outlineVersion; an unreadable kept outline is measured again. Each pair aligns once in one hop. A pair without an outline is tried again when Downloads notifies. checkInvariants checks that each alignment comes from the kept outline of its pair and that each alignment keeps its own invariants. It writes no personal record. The app wires it in t9-4v0r. The full check ran on the state of the step 6 commit (2710 passed, 21 skipped); this commit alone was checked in a separate worktree with flutter analyze lib test and flutter test test/crossings.

**2026-11-11T17:47:01Z**

Review fixes after step 7: the pair key names the audio files in play order, so a reordered recording aligns again (B1); a pair's finished work is a sealed _Aligned or _Refused (Q1); outline work in flight is shared like pair work, so two pairs of one ebook measure it once (B5, Q6); failed work is not kept (B3); a downloads change also forgets pairs in flight (B4); a measure that throws an Exception gives Refusal.unreadable (B7); prepare() starts a pair's alignment; checkInvariants checks that each finished pair is its current work's result (Q4).
