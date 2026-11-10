---
id: boo-pw1d
status: open
deps: []
links: []
created: 2026-11-10T02:10:36Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# The first reflow of a scanned PDF page can say it cannot be put in reading order, and a second try works

Seen by the user on the Pixel 8 on 2026-11-09 at about 21:07, with Nihil Unbound (a PDF in the Jellyfin library), on a release build of main installed at 21:04 (commit after ta-2hat). The user asked for the reflowed text of a page. Bookfin showed 'The text of this page cannot be put in reading order.' A second try on the same page worked. The Pixel's log shows Tesseract initialized once at 21:07:47 and no error after it. That message has two sources: _textWarning in lib/reader/pdf.dart (the PDF's own text layer) and the unreliable check in decodeRecognizedPage in lib/reader/ocr.dart (Tesseract's output). Since td-fkhd, an unreliable recognized page is saved in the recognition cache, so a cached unreliable result would repeat on the second try. Suspects: a path where the reflow view shows the extracted text layer's status before or instead of recognition (BundledEnglishText.text returns the extracted text when _closed), the page deck's neighbor views canceling the shown page's wait, or a first recognition from a raster of the wrong size whose cache write did not happen.

