# Reflow fixtures

These files hold what Bookfin's Tesseract gives for two scanned pages on an Android emulator. Ticket tb-jidt recorded them on 2026-11-10. The epic is boo-fval. The design is `docs/plans/pdf-word-image-reflow.md`.

| File | What it holds |
| --- | --- |
| `scanned-page.layout` | The layout record of the scanned page: one entry a line, its nine numbers separated by spaces. `native/ocr/bookfin_ocr.c` defines the entries. |
| `scanned-page.hocr` | The hOCR of the scanned page, from recognition after the layout pass. |
| `skewed-page.layout` | The layout record of the skewed page. |
| `skewed-page.hocr` | The hOCR of the skewed page. |

## The pages

- The scanned page is `tool/research/readers/evidence/text-quality/raven-raster-only.pdf`, SHA-256 `cd2894179a69bd874339e419924e3a89042e7302be785444a0859e390c44e7fa`. It is a byte-for-byte copy of page 9 of the Library of Congress scan of "The Raven" (Edgar Allan Poe, 1873), `https://www.loc.gov/item/unk82092576/`. The Library of Congress says: "The books in this collection are in the public domain and are free to use and reuse. Credit Line: Library of Congress." The page has an engraving, a caption, a byline, three lines of verse and a folio. It has no footnote mark, line-end hyphen or indented paragraph.
- The skewed page is that page turned by 2.5 degrees, with 300 specks of noise. `skewed_page` in `tool/reader/ocr_layout_device_test.py` makes it from the scanned page, with seed 20261110.
- The PDFs are not copied here. The device test runner makes both from their sources.

## How they were made

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
