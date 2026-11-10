# Tesseract layout pass against full recognition, on the host

Date: 2026-11-09. Epic: boo-fval. Design: `docs/plans/pdf-word-image-reflow.md`, section "The layout pass".

This is tool code and evidence. It is not product code.

## What ran

- Machine: the user's Apple silicon Mac, one thread (`OMP_THREAD_LIMIT=1`).
- Engine: Tesseract 5.5.3 from the pinned nixpkgs (`/nix/store/gz660pphrcyxy1f36prfx076zynwa2ki-tesseract-5.5.3`). Android uses Tesseract 5.5.1 through tesseract4android 4.9.0.
- Model: Bookfin's bundled `eng.traineddata` (tessdata_fast 4.1.0, SHA-256 7d4322bd…).
- Settings: `OEM_LSTM_ONLY` and `PSM_AUTO`, as `OcrChannel.kt` uses.
- Program: `bench.c`. For each image it calls `TessBaseAPIAnalyseLayout` and walks the page iterator, then `TessBaseAPIRecognize` on a fresh image, then layout and recognition on one image. It prints the best of three rounds.

## Pages

| Page | Size in pixels | How it was made |
| --- | --- | --- |
| dense | 1600 by 2093 | Nine paragraphs of 70 to 110 random common English words, set in Times New Roman at 30 points with ImageMagick `caption:`. |
| skewed | 1600 by 2600 | The dense page turned by 2.5 degrees with ImageMagick. |
| raven | 1600 by 2595 | Page 1 of `tool/research/readers/evidence/text-quality/raven-raster-only.pdf`, drawn with poppler `pdftoppm -scale-to-x 1600`. |

## Results

| Page | Layout pass | Full recognition | Recognition after the layout pass, same image | Layout words | hOCR words |
| --- | --- | --- | --- | --- | --- |
| dense | 179 ms | 1341 ms | 1160 ms | 783 | 784 |
| skewed | 218 ms | 811 ms | 595 ms | 436 | 442 |
| raven | 116 ms | 219 ms | 104 ms | 38 | 36 |

- On the dense page, the layout pass takes 13 percent of the time of full recognition. Word images can show about 1.2 seconds sooner on this Mac.
- Recognition after a layout pass on the same image reuses the layout. Together they cost about the same as full recognition alone.
- The layout pass found the skewed page's slope as 0.0430, which is 2.46 degrees.
- Layout words and hOCR words differ in count. So text attaches to layout words by box overlap, not by index.

The phone numbers are not known yet. Ticket tb-bmmm measures the same comparison on an Android emulator.
