# Tesseract's layout pass on an Android emulator, through the C API

Date: 2026-11-10. Ticket: tb-t0ea. Epic: boo-fval. Design: `docs/plans/pdf-word-image-reflow.md`, section "The layout pass".

This folder is evidence. It is not product code.

## What ran

- Emulator: the AVD `bookfin-tb-t0ea`, made for this ticket from `system-images;android-36;google_apis;arm64-v8a` (Pixel 7 profile, 4 cores, 2 GB). It ran on the user's Apple silicon Mac and was deleted afterward.
- Engine: tesseract4android 4.9.0 (Tesseract 5.5.1) with the bundled `eng.traineddata` (tessdata_fast 4.1.0).
- Pages: PDFium drew each page 1600 pixels wide, as `_recognizePage` does. `tool/reader/ocr_layout_device_test.py` made the test pages and served them to the emulator.
  - `scanned.pdf` is `tool/research/readers/evidence/text-quality/raven-raster-only.pdf`: an engraving, a title, a byline, three lines of verse and a folio.
  - `skewed.pdf` is that scan turned by 2.5 degrees, with 300 specks of noise.
  - `nist-cloud.pdf`, `census-notice.pdf` and `raven-1873.pdf` are the pinned PDF corpus of `tool/reader/fetch_pdf_corpus.py`.
- Debug build, so the times are only a first look. Ticket tb-bmmm measures properly.

## Files

| File | What it shows |
| --- | --- |
| `red.txt` | Before the change: every layout test fails because the channel has no `layout` method. |
| `java-engine-before.txt` | Before the change: the hOCR digests of the Java `TessBaseAPI` engine on 8 pages, in two rounds. The rounds agree. |
| `worker-red.txt` | Before the worker change: the worker does not admit a layout pass. |
| `red-picture-and-slope.txt` | Before the walk skipped them: the engraving's pseudo line and word, and its flat baseline among the skewed page's lines. |
| `green.txt` | After the change: all 6 device tests pass. |
| `corpus-sweep.txt` | After the change: 35 of 35 pages give the same hOCR after the layout pass as alone. These are all pages of the 3 corpus PDFs, and the 2 test pages. |

## Byte identity

- On all 35 pages, recognition after the layout pass gave the same hOCR, byte for byte, as recognition alone.
- On the 8 pages of `java-engine-before.txt`, the C API engine gave the same hOCR as the Java engine before the change. The test `recognition after the layout pass gives the same hOCR, byte for byte, as recognition alone, and as the Java engine gave` checks the digests.

## Times on the emulator (debug build, one run)

| Page | Size in pixels | Layout pass | Recognition after the layout pass | Recognition alone | Layout words | hOCR words |
| --- | --- | --- | --- | --- | --- | --- |
| scanned | 1600 by 2594 | 116 ms | 88 ms | 226 ms | 36 | 35 |
| skewed | 1600 by 2594 | 115 ms | 95 ms | 211 ms | 42 | 41 |
| nist-cloud page 3 | 1600 by 2070 | 111 ms | 501 ms | 619 ms | 189 | 188 |
| nist-cloud page 6 | 1600 by 2070 | 192 ms | 1321 ms | 1510 ms | 514 | 514 |
| census-notice page 1 | 1600 by 2070 | 342 ms | 2581 ms | 2876 ms | 925 | 916 |
| census-notice page 2 | 1600 by 2070 | 347 ms | 2588 ms | 2813 ms | 918 | 917 |
| raven-1873 page 12 | 1600 by 2598 | 137 ms | 713 ms | 855 ms | 272 | 275 |
| raven-1873 page 13 | 1600 by 2598 | 131 ms | 219 ms | 360 ms | 96 | 98 |

- The three densest pages are nist-cloud page 6 and census-notice pages 1 and 2. On them, the layout pass takes 12 to 13 percent of the time of recognition alone. On the lighter pages it takes 16 to 54 percent.
- Tesseract and its libraries are prebuilt release code, so a debug build changes only the Dart side of these times.
- The layout pass and the recognition after it together take about as long as recognition alone, as on the host.
- The skewed page's four lines wider than 400 pixels slope by 2.46, 2.38, 2.52 and 2.33 degrees.
