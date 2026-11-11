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

**2026-11-11T19:39:40Z**

Measured on 2026-11-11 with the shipped code (buildBooks, possibleMatches, audioOutline, measureDownloadedOutline, alignEditions) in a scratch test outside the repository. The result is in docs/plans/cross-edition-places.md, 'Measured on the user's library'.

- The server holds 1,478 audiobook files and 24 ebooks (12 EPUB, 12 PDF). Only 2 books have both editions (3 pairings, both EPUB). So the measurement added 15 pairings of the user's recordings of 9 public-domain works with corpus EPUBs.
- 24.2% of the recordings have no chapter marks. 30.7% have generic track or file names or bare numbers.
- Design A refuses 10 of 18 pairings (56%): 7 partCovered, 2 fewMatches, 1 noChapters. Of the 8 matches, 5 have wrong anchors: track numbers that pair with chapter numbers by chance, and one collection ebook.
- No rate band separates right from wrong pairings. Recommendation for the parent: keep the band and the one-page margin, lower the coverage limit to 0.3, and add a self-check that refuses a pairing whose median leave-one-out error exceeds 2 pages. No production code changed.
- New ticket t5-gk30: Bookfin cannot open 3 of the user's 12 EPUBs.
- The Jellyfin 12.4 server refused the X-Emby-Token header, so the read-only requests sent the key in the Authorization header. The scratch files are deleted.
