---
id: boo-981b
status: open
deps: []
links: []
created: 2026-11-09T17:56:11Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Open a PDF quietly on its original page, and reflow it on demand with no notices

Requested by the user on 2026-11-09, with a screenshot of the PDF reader on the Pixel (Nihil Unbound, reflowed).

1. Remove every disclaimer notice that pops over a reader page: "Extracted text is not checked against the page. Pictures and page layout stay in the original page." (lib/reader/pdf_viewport.dart), "English scans only. Other languages are not supported.", and every other such notice in the app. The user said they ruin the reading experience.
2. A PDF always opens on its original pages. Opening a PDF never offers or asks about recognition (OCR). Today a prompt to recognize text appears at the first open, even when the PDF has a text layer, and it stays until the user chooses reflow once.
3. When the user switches to the reflow view, the reader reflows the page. It runs recognition by itself only on a page that has no usable text layer, without asking. It shows no notice about it.
4. A message appears only when reflow cannot work on the shown page (for example recognition failed or found no text), and only in the reflow view, as a quiet line in place of the text, not as a pop-over. The original view is always one tap away.

Check whether ticket tf-0wci (reader notices on macOS) is still needed after this.

