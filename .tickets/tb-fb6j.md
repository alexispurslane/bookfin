---
id: tb-fb6j
status: open
deps: [tb-9mcf, tb-mfkk, tb-fi98, tb-bmmm, tb-zx7r, tb-valc, tb-nkz5, tb-m8xo, boo-wfg1]
links: []
created: 2026-11-10T02:33:42Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Accept PDF word reflow on the Pixel 8 and tune its word size

W10 of docs/plans/pdf-word-image-reflow.md (Device acceptance). Use the T3 device tools only. Open the three fixtures and one scanned book from the user's library. Screenshots of the word view in cream and night at sizes 14, 20 and 40, and of the text view. Tune _wordSizeRatio once against an EPUB at size 20. Measure the time from a turn to the first screen of a page with cached text, the time from a turn to a never-recognized scanned page's first word screen and to its text, graphics memory over ten turns, and dropped frames on turns inside a page. Use the emulator numbers of tb-bmmm as the baseline.

## Acceptance Criteria

The first screen of a page with cached text shows within 400 ms on the Pixel 8, or the ticket records the measured time and a follow-up ticket. Graphics memory stays within the band bound. Turns inside a page drop no frame. Screenshots and measurements are saved under tool/evidence and shown to the user for acceptance.


## Notes

**2026-11-10T20:10:25Z**

User accepted the Nihil Unbound crop repair and Trim margins toggle on the Pixel 8. Remaining product scope is word-image reflow (the printed words cut into images and wrapped to the screen), with its planned interactions. Do not repeat crop/toggle acceptance unless integration changes that behavior.
