---
id: boo-sy2d
status: closed
deps: [boo-yjq6]
links: []
created: 2026-11-11T20:09:32Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-tam0
---
# Open books faster: design A, admit at download and show the kept last page

Design A of docs/plans/faster-book-open.md, chosen by the user 2026-11-11.


## Notes

**2026-11-11T23:22:22Z**

User 2026-11-11: do the MOBI to EPUB conversion when the download completes. Design A's download-time admission must include the libmobi conversion and keep the converted EPUB, so a MOBI's first open takes the cached path like an EPUB (measured: conversion 253 ms of the MOBI's 508 ms first open after the quick wins).

**2026-11-12T00:26:47Z**

Step 1 (admission at download): Downloads takes a prepare hook (LocalDownloads.prepare). It prepares each saved file of a text edition once its download completes and again after each restoration at launch, one at a time, under a hold of the download. prepareDownloadedBook (lib/reader/platform_io.dart) admits an EPUB and keeps its admitted record; for a MOBI, prepareMobi converts it with libmobi, keeps the converted EPUB, and keeps the admitted record. A PDF needs no preparation. A load that starts during a preparation waits for it and reads the record (AdmittedBooks.written). A preparation whose record is current reads only the key line and does nothing more. A failed preparation leaves the download whole and shows nothing.

**2026-11-12T00:55:45Z**

Step 2 (the kept page): layout records the builder calls of each paragraph that a page can show (ParagraphRecipe, recipeOf). KeptPage (lib/reader/epub/kept_page.dart) encodes a laid page as those recipes, the paragraph widths and the page-relative places of its pieces and decorations, and builds them again; drawPage takes either page (PageDrawing). KeptPages (lib/reader/kept_pages.dart) keeps one file per download, .bookfin-layout/last-page: a key line (codec format, text-engine fingerprint, file digest, saved place), the CRC-32 of the body, and the body, written atomically under a hold. A read with another key or a bad CRC gives nothing. A page that draws with a font of the book is not kept. The session reads the kept page of the saved place while the book loads, keeps the shown page at flush and at close, and drops the kept page when the pager shows its first page. EpubViewport takes a nullable pager and a kept page: it draws the kept page when its settings equal the viewport's, holds taps and turns until the first true page, and applies them in order only when the kept page depicts that page. The screen shows the paper while the kept page is read, and the spinner only when none was kept.

**2026-11-12T01:52:00Z**

Review (one reviewer, changes required) resolved: B1/Q1 the session keeps the shown page only when EpubPager.opensAtShown (a main run cut it and it holds the place that the pager reported last), test 'a page kept after a jump into the middle of a page and a new text size...' (red without the check). B2 depicts compares numbers within 1/1000 px (KeptPage.alike), and the encoder cuts rules to the rows that drawPage's clip shows plus 1 px, test 'a kept page depicts its page when a run from that page cut it, as a reopen does...' over the sample sections and odd settings (red before). B3 _keepShown catches every failure, and flush saves the place before it keeps the page. B4 a failed preparation keeps its key (.bookfin-admitted/failed) and the next preparation with that key does nothing; the open still admits. B5 one set of text-source ids per restoration. B6 a PDF edition reads no kept page. Q2 KeptPages.write skips a page that the file keeps already, and the key uses encodeTextPosition; the session keeps no copy. Q4 AdmittedBooks.prepare takes its own hold. Q5 _held has a documented, checked invariant. Q6 RunStyle owns toJson/fromJson, with a round-trip test. F4 a lent file goes through prepareDownloadedBook for an EPUB and a MOBI (red when the MOBI closure captures it). The session tests now wait until the open's load started before they read readingKeptPage (they were vacuous). Q7: recipe recording measured on host, 400-paragraph section: median 87.6 ms with, 86.2 ms without (noise). Left: B7 (an open in the few milliseconds before prepareDownloadedBook registers its write admits in parallel; a removal can wait up to one preparation), Q3 (VerifiedFile keeps its hold closure; the F4 test guards worker captures).

**2026-11-12T03:24:45Z**

Merged to main at 2ca16904 (orchestrator finished the merge after the agent's disk filled). Emulator-5560 medians, drawn page, 3 pairs per book, load 8 to 18: first open after download before/after prose 149.9/61.9, long 203.0/63.0, illustrated 221.8/70.7, divine 392.3/76.1, wealth MOBI 604.7/56.3 ms. Reopen before 34 to 40 ms of blank paper; after, the kept page shows at 9.0 to 10.4 ms and the true page at 32.8 to 38.6 ms (no delay within noise). Kept page matched the true page in 45 of 45 reopens. Kept page file 1.6 to 4.3 KB per opened book. Check on the merged tree: format clean, analyze clean, 3017 passed, 25 skipped, 1 failed (t3-5o5r, passed 3 of 3 alone).
