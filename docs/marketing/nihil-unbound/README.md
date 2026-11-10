# Nihil Unbound: the same page before and after

Captured on November 10, 2026 for `boo-qn2i`, using Bookfin revision `bfcbe24b7c6ef6324c6769d02c40cf236ebd5ed0`.
These are real renders of the production `PdfViewport` on a computer through Flutter's host test runner.
They are not Android screenshots, HTML reconstructions, or device-performance evidence.

## Authorized excerpt

The user supplied Ray Brassier's *Nihil Unbound: Enlightenment and Extinction* and expressly authorized a limited screenshot excerpt for this homepage.
This is not a public-domain claim or permission to redistribute the book.
Only three views of one source page are committed. The source PDF and extracted text are not committed.

All three assets use PDF source page 24, numbered from 1, which is printed page 9 in chapter 1, “The Apoptosis of Belief.”
It is body prose, not a title page or frontmatter. It includes a quotation, italics, paragraph breaks, and a later section heading.
The Original image shows the whole page. Each Page words image shows the first screen of that same page, not a different page with larger print.

The supplied PDF's SHA-256, a fingerprint of its bytes, is recorded in `assets.json`.
No personal library paths, server addresses, or account details are needed to reproduce the rendering.

## Capture method

An ignored scratch harness, `.cache/qn2i_pdf_capture_test.dart`, opens the supplied bytes with `PdfRuntime.instance.open` and the pinned native PDFium library from the Nix development shell.
It uses the real PDF text layer and production word geometry, page analysis, word-image rendering, and line layout.
No replacement text, synthetic word boxes, OCR fixtures, or HTML are substituted for this book.

The harness mounts `PdfViewport` in a `Scaffold` with `bookfinTheme`, then captures a `RenderRepaintBoundary` after the view is ready.
Original readiness requires a populated page image. Page words readiness requires a rendered word screen with its selection text attached.
Each capture starts at `PdfAddress(24, 0, pageCount: book.pageCount)`, with margin trimming off.
The viewport is 411 by 840 logical pixels, with two image pixels per logical pixel; each PNG and WebP is 822 by 1680 pixels.

| Asset | Production view | Theme | Size setting |
| --- | --- | --- | --- |
| `original.webp` | Original, whole source page | Cream around the source page | 20, unused by Original |
| `page-words-cream.webp` | Page words, first screen | Cream | 24 |
| `page-words-night.webp` | Page words, first screen | Night | 28 |

The size and line breaks visibly differ between Cream and Night. The Night capture shows less of the same page because its words are larger.
The Original page keeps its white source paper; Page words uses the selected theme's paper and ink.
The source page has no figure or chart. Retained illustration evidence remains available in the earlier [public Raven comparison](../pdf-reflow/README.md).
That evidence and the implementation references below support the image-retention copy; this prose example is not a universal chart-extraction test.

PNG captures were encoded to WebP at quality 84, method 6, without cropping, retouching, compositing, or replacing app contents.
`assets.json` records both raw PNG and final WebP hashes, dimensions, and byte counts.

## Commands and result

The final capture command ran the PDF and History harnesses one at a time:

```sh
nix develop --command flutter test --no-pub --concurrency=1 .cache/qn2i_pdf_capture_test.dart .cache/qn2i_history_capture_test.dart --reporter expanded
```

Both capture tests passed, with no Flutter exception. Scratch scripts and raw PNGs stay ignored, outside the application test suite.
The local final log is `.cache/qn2i-captures-final.log`.
Flutter printed optional missing-iOS-SDK notices. No device or emulator was opened or controlled.

Before selecting the excerpt, native probes checked candidate pages without saving their text.
PDF pages 11 and 14 rendered but were rejected as frontmatter; page 23 rendered but page 24 showed more useful paragraph structure and italics.
Pages 18–22 had an unreliable text layer and no native word geometry in this revision. A trial on page 18 did not reach Page words readiness.
Those trial assets are not published, and no production reader changes were made to hide that limitation.

## Product-copy references

These source and existing test references were inspected at the renderer revision above. They are not claims of a new full-suite run.

| Homepage claim | Implementation | Existing behavior evidence |
| --- | --- | --- |
| Original, Page words, and Text choices | `lib/reader/pdf.dart:24`, `lib/reader/pdf_viewport.dart:704` | `test/reader/pdf_word_view_test.dart:705` |
| Source word images, not a replacement font | `lib/reader/word_pages.dart:63`, `lib/reader/word_bands.dart` | `test/reader/word_pages_test.dart:185` |
| Adjustable size and wrapping | `lib/reader/session.dart:1347`, `lib/reader/column_layout.dart:309` | `test/reader/pdf_word_view_test.dart:1268` |
| Complete lines at screen turns | `lib/reader/column_layout.dart:50`, `lib/reader/screen_cut.dart` | `test/reader/column_layout_test.dart:675` |
| Headings, paragraph breaks, and indents shape the flow | `lib/reader/column_layout.dart:309`, `lib/reader/column_layout.dart:597` | `test/reader/column_layout_test.dart:433`, `test/reader/column_layout_test.dart:471` |
| Pictures and ink regions stay whole | `lib/reader/page_analysis.dart:6`, `lib/reader/column_layout.dart` | `test/reader/column_layout_test.dart:291`, `test/reader/column_layout_test.dart:522`, `test/reader/column_layout_test.dart:587` |
| Cream and Night paper and ink | `lib/reader/word_pages.dart:102`, `lib/reader/word_pages.dart:128` | `test/reader/word_pages_test.dart:555` |
| Selection, Copy, and search when text is available | `lib/reader/pdf_viewport.dart:104`, `lib/reader/pdf_viewport.dart:546`, `lib/reader/pdf.dart:867`, `lib/reader/session.dart:1387` | `test/reader/pdf_word_view_test.dart:965`, `test/reader/pdf_word_selection_test.dart:245` |
| Optional blank-margin trimming | `lib/reader/session.dart:1326`, `lib/reader/pdf_viewport.dart:785` | `test/reader/pdf_crop_test.dart` |
| Downloaded PDFs and English scan recognition work offline | `lib/reader/session.dart`, `lib/reader/ocr.dart`, `android/app/src/main/kotlin/dev/bookfin/bookfin/OcrChannel.kt:118` | `test/reader/ocr_downloads_test.dart`, `test/reader/ocr_native_test.dart` |

The current size control ranges from 14 to 40. The homepage does not promise unlimited sizes or identical page layout after reflow.
Picture colors are preserved on light paper with the implemented paper tint; Night dims pictures. Ink regions take the theme's ink.
The homepage does not claim universal layout or chart recognition, nor durable per-book PDF view and trim choices.

See `../boo-qn2i-verification.json` for the asset, markup, and layout checks, and [shared History notes](../shared-history/README.md) for that capture.
