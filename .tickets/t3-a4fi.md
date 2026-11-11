---
id: t3-a4fi
status: in_progress
deps: []
links: []
created: 2026-11-11T15:39:12Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-z3is
---
# Measure how the audiobook chapters of the user's library match their ebook contents

Found during the design of boo-z3is (docs/plans/cross-edition-places.md). The design measured chapter matching only on public data: 155 LibriVox recordings against 39 public-domain EPUB editions. The user's Jellyfin library holds commercial audiobooks whose chapter marks come from publishers or ripping tools ("Chapter 1", "Track 01", "Opening Credits", or none). Its saved copies on this Mac and on the shared emulators hold only the demonstration library. So this measurement needs a sign-in through T3's private secret input.

For every book that has an audio edition and an EPUB or MOBI edition, measure these facts:

- Whether the audio edition has chapter marks.
- How its chapter titles read: number only, number and words, words only, generic names such as Track 01, or file names.
- How many audio chapters and ebook contents entries it has.
- How many anchors the matcher of tool/research/cross_edition/measure.py finds after its rate check and ordinal fill.

Report the share of books that design A of the plan refuses. Print counts and title patterns only. Never print or commit the server address or private titles beyond a few anonymized examples. Use the result to set the thresholds of the edition alignment ticket.


## Notes

**2026-11-11T19:22:24Z**

Measurement agent started (Claude Opus 5.5 high, worktree, read-only on the server). Key delivered through T3 private secret input as a file; agent may not print or commit it or the address.
