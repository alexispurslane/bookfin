# Reflow fixtures

These files hold what Bookfin's Tesseract gives for three scanned pages on an Android emulator, and one born-digital page. Ticket tb-jidt recorded the scanned and skewed pages on 2026-11-10. Ticket tb-xwlj added the born-digital page, and ticket t2-jfg1 added the footnote page, on the same day. The epic is boo-fval. The design is `docs/plans/pdf-word-image-reflow.md`.

| File | What it holds |
| --- | --- |
| `scanned-page.layout` | The layout record of the scanned page: one entry a line, its nine numbers separated by spaces. `native/ocr/bookfin_ocr.c` defines the entries. |
| `scanned-page.hocr` | The hOCR of the scanned page, from recognition after the layout pass. |
| `skewed-page.layout` | The layout record of the skewed page. |
| `skewed-page.hocr` | The hOCR of the skewed page. |
| `footnote-page.pdf` | The footnote page: one scanned page, with no text layer. |
| `footnote-page.layout` | The layout record of the footnote page. |
| `footnote-page.hocr` | The hOCR of the footnote page. |
| `equation-page.typ` | The Typst source of the equation page. |
| `equation-page.pdf` | The equation page, made from `equation-page.typ`. |

## The pages

- The scanned page is `tool/research/readers/evidence/text-quality/raven-raster-only.pdf`, SHA-256 `cd2894179a69bd874339e419924e3a89042e7302be785444a0859e390c44e7fa`. It is a byte-for-byte copy of page 9 of the Library of Congress scan of "The Raven" (Edgar Allan Poe, 1873), `https://www.loc.gov/item/unk82092576/`. The Library of Congress says: "The books in this collection are in the public domain and are free to use and reuse. Credit Line: Library of Congress." The page has an engraving, a caption, a byline, three lines of verse and a folio. It has no footnote mark, line-end hyphen or indented paragraph.
- The skewed page is that page turned by 2.5 degrees, with 300 specks of noise. `skewed_page` in `tool/reader/ocr_layout_device_test.py` makes it from the scanned page, with seed 20261110.
- The PDFs of these two pages are not copied here. The device test runner makes both from their sources.
- The footnote page is page 19 of volume 4 of "The History of the Decline and Fall of the Roman Empire" (Edward Gibbon, with notes by H. H. Milman and F. Guizot, Philadelphia: Nottingham Society, dated 1880). The Internet Archive item is `historyofdecline004gibb`, scanned from the University of Connecticut Libraries at 500 pixels per inch. The page image is `https://archive.org/download/historyofdecline004gibb/page/n30.jpg`, 1853 by 3092 pixels, SHA-256 `83dffaf6f48f32df682d31f3cc5c6456c469a3d7a6ffd0063ce37a68c8876572`, as downloaded on 2026-11-10. The book was published before 1929, and its authors died in 1794, 1868 and 1874, so it is in the public domain in the United States and in countries with terms of life plus 70 years.
- `footnote-page.pdf` holds that JPEG unchanged, as the only image of a page 266.83 by 445.25 points (500 pixels per inch). `python3 tool/reader/jpeg_page_pdf.py n30.jpg footnote-page.pdf 500` made it. Its SHA-256 is `c96b8a9682ba86ff0ee20b659682e62b6bcf1533c84a0c0cb2618f0ede024459`.
- The footnote page has a running header with a folio, 24 lines of prose with six line-end hyphens, footnote marks 18 to 21 raised after words, italics, an indented paragraph ("The name of the Alemanni"), a side note ("A.D. 491") in the margin, and five footnotes in smaller type. It has no figure.

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
- On the footnote page, the layout pass found 465 words and recognition found 468. The layout pass marks "The name of the Alemanni" as a paragraph start with a first-line indent of 49 pixels. Neither pass gives the raised footnote marks 18 to 21 a word of their own. Mark 18, after "city.", is ink between two words. Recognition reads marks 19 to 21, after "pusillanimous", "Tongres," and "lake.", as a closing quotation mark at the end of the word. Footnote 17 continues from the page before, so its mark is not on this page. Ticket t2-jfg1 recorded both files on the AVD `bookfin-t2-jfg1`, made the same way as `bookfin-tb-jidt` and deleted afterward.
