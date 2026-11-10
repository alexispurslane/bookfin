# Reflow fixtures

These files hold what Bookfin's Tesseract gives for two scanned pages on an Android emulator, and one born-digital page. Ticket tb-jidt recorded the scanned pages on 2026-11-10. Ticket tb-xwlj added the born-digital page on the same day. The epic is boo-fval. The design is `docs/plans/pdf-word-image-reflow.md`.

| File | What it holds |
| --- | --- |
| `scanned-page.layout` | The layout record of the scanned page: one entry a line, its nine numbers separated by spaces. `native/ocr/bookfin_ocr.c` defines the entries. |
| `scanned-page.hocr` | The hOCR of the scanned page, from recognition after the layout pass. |
| `skewed-page.layout` | The layout record of the skewed page. |
| `skewed-page.hocr` | The hOCR of the skewed page. |
| `equation-page.typ` | The Typst source of the equation page. |
| `equation-page.pdf` | The equation page, made from `equation-page.typ`. |

## The pages

- The scanned page is `tool/research/readers/evidence/text-quality/raven-raster-only.pdf`, SHA-256 `cd2894179a69bd874339e419924e3a89042e7302be785444a0859e390c44e7fa`. It is a byte-for-byte copy of page 9 of the Library of Congress scan of "The Raven" (Edgar Allan Poe, 1873), `https://www.loc.gov/item/unk82092576/`. The Library of Congress says: "The books in this collection are in the public domain and are free to use and reuse. Credit Line: Library of Congress." The page has an engraving, a caption, a byline, three lines of verse and a folio. It has no footnote mark, line-end hyphen or indented paragraph.
- The skewed page is that page turned by 2.5 degrees, with 300 specks of noise. `skewed_page` in `tool/reader/ocr_layout_device_test.py` makes it from the scanned page, with seed 20261110.
- The PDFs are not copied here. The device test runner makes both from their sources.

## The equation page

`equation-page.pdf` is a born-digital A5 page with a usable text layer. It has a centered heading, two paragraphs with inline formulas and a superscript, a display equation with raised marks, a small table, and a justified paragraph with wide word gaps and a line-end hyphen. Its SHA-256 is `a57261ff6007278b087f5b4d64ee42056afa5b31c185f7d18ea6c3d9a75a3fd1`.

- Ticket tb-xwlj wrote `equation-page.typ` and dedicates it and the PDF to the public domain under CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/).
- The PDF embeds subsets of Libertinus Serif (Regular and Bold), under the SIL Open Font License 1.1, and New Computer Modern Math, under the GUST Font License. Typst bundles both fonts.
- The display equation has no stacked fraction. Both stacked fractions that tb-xwlj tried made Bookfin's reading order check reject the text layer. Then the page takes its text from recognition, and its character boxes give no words.

To make it again, run this in the dev shell, in this folder:

```sh
typst compile --ignore-system-fonts equation-page.typ equation-page.pdf
```

The output is the same, byte for byte, for the Typst that the flake pins (0.15.1). Its reading text and digest are locked in `test/reader/text_layer_geometry_test.dart`.

## How the scanned pages were made

- Emulator: the AVD `bookfin-tb-jidt`, from `system-images;android-36;google_apis;arm64-v8a`, on the user's Apple silicon Mac. It was deleted afterward.
- Engine: tesseract4android 4.9.0 (Tesseract 5.5.1) through `native/ocr/bookfin_ocr.c`, with the bundled `eng.traineddata` (tessdata_fast 4.1.0).
- PDFium drew each page 1600 pixels wide, as Bookfin does for the layout pass and recognition.

To record them again, run this in the dev shell on your own emulator:

```sh
python3 tool/reader/ocr_layout_device_test.py <serial> --name "reflow fixtures" --record test/reader/fixtures/reflow
```

Without `--record`, the device test `the reflow fixtures hold the layout records and the hOCR that the emulator gives` makes sure that the emulator still gives these files.

## Checks

- The SHA-256 of `scanned-page.hocr` is `4d8ad2eaa2224311bedc7261eb9930ebd8b31ee816cd1305d50d4adeaf837c9d`. The SHA-256 of `skewed-page.hocr` is `9417203aa4398f3f761605c516edd5d04e448ea7a2ad81348e7be14efdc1f1a1`. Both equal the hOCR that the Java engine gave before ticket tb-t0ea (`integration_test/ocr_layout_test.dart`).
- The layout pass found 36 words on the scanned page and 42 on the skewed page. Recognition found 35 and 41.
