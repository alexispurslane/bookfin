---
id: boo-pw1d
status: closed
deps: []
links: [te-h8ip]
created: 2026-11-10T02:10:36Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# The first reflow of a scanned PDF page can say it cannot be put in reading order, and a second try works

Seen by the user on the Pixel 8 on 2026-11-09 at about 21:07, with Nihil Unbound (a PDF in the Jellyfin library), on a release build of main installed at 21:04 (commit after ta-2hat). The user asked for the reflowed text of a page. Bookfin showed 'The text of this page cannot be put in reading order.' A second try on the same page worked. The Pixel's log shows Tesseract initialized once at 21:07:47 and no error after it. That message has two sources: _textWarning in lib/reader/pdf.dart (the PDF's own text layer) and the unreliable check in decodeRecognizedPage in lib/reader/ocr.dart (Tesseract's output). Since td-fkhd, an unreliable recognized page is saved in the recognition cache, so a cached unreliable result would repeat on the second try. Suspects: a path where the reflow view shows the extracted text layer's status before or instead of recognition (BundledEnglishText.text returns the extracted text when _closed), the page deck's neighbor views canceling the shown page's wait, or a first recognition from a raster of the wrong size whose cache write did not happen.


## Notes

**2026-11-10T02:44:18Z**

Investigation on 2026-11-09 (no code change). Nihil Unbound is a typeset PDF, not a scan. Its own text layer is a candidate on pages 2-7, 11, 14-17, 23-26 and 33, and _textWarning marks pages 1, 8-10, 12-13, 18-22 and 27-32 as out of order. On a new AVD with a profile build of main and the real file, choosing Reflow showed a thin progress line and then the recognized text on pages 12, 27 and 28, including page 28 as the first recognition after a fresh start (Tesseract initialized then). It showed 'The text of this page cannot be put in reading order.' on page 1 (the cover) and pages 8 and 9 (contents), on the first try and on every later try, after recognition finished. Host Tesseract 5.5.3 with the bundled eng model, on page 1 rendered 1600 pixels wide, gives five lines ('Oalgrave', 'macmillan', 'Nihil Unbound', 'Enlightenment and Extinction', 'Ray Brassier'); decodeRecognizedPage marks that unreliable because 4 of 5 lines have two words or fewer. So on these pages the message is the final outcome of recognition, cached since td-fkhd, and it repeats. Four widget sequences with the real BundledEnglishText (choose reflow; reflow off and on during recognition; open in reflow; turn away and back during recognition) showed no reason while text was on its way. No sequence that shows a false reason was found. Likely explanation, not confirmed: the book opened at source page 1, the cover failed for the rule above, and the second try reached page 2 or 4 (half-title and title page, same title, usable text layers). Ask the user for the source page label of the failed page. See te-h8ip for the cover rule.

**2026-11-10T12:53:55Z**

Closed after investigation: no race. The message is the final result of recognition's short-line and parallel-row rule on covers and contents pages. te-h8ip carries the user's fix (show such pages as printed, no message).
