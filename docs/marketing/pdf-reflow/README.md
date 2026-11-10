# Homepage PDF comparison

Captured on November 10, 2026 for `boo-54l1`.
These are Bookfin host-renderer captures: the production PDF viewport rendered on a computer through Flutter's test runner.
They are not Android screenshots, HTML recreations, or evidence of device performance.

## Public source

All three images use the same PDF page and the same source bytes.
The page is scan page 9 of Edgar Allan Poe's *The Raven* (1873), with printed folio 1.
It contains an engraving, its caption, a byline, and three lines of verse.
The first page of the one-page fixture is that entire scanned page.

Source: <https://www.loc.gov/item/unk82092576/>.
Credit: Library of Congress.
The Library of Congress item identifies the book as public domain and free to use and reuse.
Its item metadata was fetched again on the capture date and confirmed the title, year, and reuse statement.
The original source record is also in [the fixture provenance](../../../test/reader/fixtures/reflow/README.md).
The fixture is public research material, not a book from a private library.

| Input | Repository path | SHA-256 |
| --- | --- | --- |
| Original PDF | `tool/research/readers/evidence/text-quality/raven-raster-only.pdf` | `cd2894179a69bd874339e419924e3a89042e7302be785444a0859e390c44e7fa` |
| Recorded word geometry | `test/reader/fixtures/reflow/scanned-page.layout` | `6cdc1745867a09dcfd62bea3249a49749adfddadd12e8eed2f21c408fde92bcc` |
| Recorded recognition text | `test/reader/fixtures/reflow/scanned-page.hocr` | `4d8ad2eaa2224311bedc7261eb9930ebd8b31ee816cd1305d50d4adeaf837c9d` |

The geometry describes the positions of words and figures on the source page.
The recognition text comes from the existing Android recognition fixture.
Neither was rewritten for the homepage.

## Capture method

Renderer revision: `c9200c085612a0978dd56d4fa1ac943c1f92a67d`.
The capture did not change application code.
It used the pinned project Nix development shell, Flutter 3.47.4, and the host PDFium library selected by `PDFIUM_LIBRARY`.
PDFium is the library that draws the source PDF.

An ignored capture harness at `.cache/marketing_capture_test.dart` opened the PDF with `PdfRuntime.instance.open`.
It supplied the existing `FixtureRecognition('scanned-page')` from `test/reader/page_analysis_test.dart`.
This supply reuses recorded recognition results. It does not pretend to run Android recognition on the host.

Each capture mounted the real `PdfViewport` in a `Scaffold`, with the production `bookfinTheme`.
Original used `PdfPageView.original`. The reflow captures used `PdfPageView.pageWords`.
Margin trimming was off in all three captures.
Each viewport measured 411 by 960 logical pixels, with two image pixels per logical pixel.
The resulting images measure 822 by 1920 pixels.

The harness waited for the original page image, or for `WordScreenView` to hold a rendered screen and its text to finish attaching.
It then captured the `RenderRepaintBoundary` as PNG.
No text, image, page chrome, or control was drawn outside the production widgets.
The only post-processing was WebP compression at quality 84 with ImageMagick's WebP method 6.
There was no cropping, compositing, resizing, retouching, or removal of renderer defects.

| Asset | View | Theme | Size control | Screen shown |
| --- | --- | --- | --- | --- |
| `raven-original.webp` | Original | Cream | Not applicable to Original | Entire source page, fitted to the viewport |
| `raven-page-words-cream.webp` | Page words | Cream | 24 | First screen of the same source page |
| `raven-page-words-night.webp` | Page words | Night | 28 | First screen of the same source page; verse continues on the next screen |

The figure remains source imagery in both themes. Night dims that imagery, as implemented in `lib/reader/word_pages.dart:128`.
The word images use the theme's paper and ink.
The line breaks change with the size control; this is not a claim of identical page layout after reflow.
This example shows an engraving, not a measured chart-extraction acceptance run.

The local capture command was:

```sh
nix develop --command flutter test --no-pub .cache/marketing_capture_test.dart --reporter expanded
```

The harness stays in ignored scratch space rather than the application test suite.
The final run passed its one capture test and reported no Flutter exceptions.
Flutter also printed notices about missing optional iOS SDKs. No device or emulator was used.
The raw PNG files remain in ignored `.cache/marketing-originals/` in the implementation worktree.
The committed `assets.json` records the output dimensions, sizes, and hashes.

## Homepage claim sources

The following references were inspected at the renderer revision above.
They establish the copy's current meaning. They are not new test results from this content task.

| Claim | Implementation | Existing behavior tests |
| --- | --- | --- |
| Original, Page words, and Text are distinct PDF views | `lib/reader/pdf.dart:24`, `lib/reader/pdf_viewport.dart:704` | `test/reader/pdf_word_view_test.dart:705` |
| Page words uses source images and retains image regions | `lib/reader/word_pages.dart`, `lib/reader/word_bands.dart`, `lib/reader/page_analysis.dart:6` | `test/reader/word_pages_test.dart:185` |
| The size control is adjustable, not unlimited | `lib/reader/session.dart:1348`, `lib/reader/screen.dart:157` | `test/reader/pdf_word_view_test.dart:1268` |
| Reading positions and bookmarks survive reopening | `lib/reader/session.dart:1433` | `test/reader/session_test.dart:101` |
| Reading moves and bookmarks are saved and restored | `lib/reader/session.dart:941`, `lib/reader/session.dart:1215`, `lib/reader/session.dart:1487` | `test/reader/reading_timeline_test.dart:95`, `test/reader/reading_timeline_test.dart:114`, `test/reader/reading_timeline_test.dart:167` |
| Listening history survives restart and supports return jumps | `lib/playback/playback.dart:374`, `lib/playback/playback.dart:1647` | `test/playback/history_test.dart:288`, `test/playback/history_test.dart:345` |
| History merges reading and listening entries, newest first | `lib/playback/timeline.dart:32`, `lib/playback/timeline.dart:86` | `test/playback/shared_timeline_test.dart:201` |
| History opens from the player, reader, and book details | `lib/playback/screen.dart:213`, `lib/reader/screen.dart:131`, `lib/catalog/book_page.dart:270` | `test/playback/shared_timeline_test.dart:144`, `test/reader/dock_history_test.dart` |
| Go to opens the medium of the chosen history entry | `lib/playback/timeline.dart:53`, `lib/playback/timeline.dart:113` | `test/playback/shared_timeline_test.dart:247`, `test/playback/shared_timeline_test.dart:305` |

The size control currently ranges from 14 to 40.
The homepage says “adjustable size,” not “any size” or “unlimited.”
Both history tickets `t9-9ffz` and `t9-7fxw` are closed in this revision.

Both `timeline()` methods return actions and bookmarks only.
They do not add a pair of live resume rows for the current audiobook and ebook positions.
The homepage advertises shared histories and jumps between media, not two current locations displayed together.
It does not claim that PDF view and margin choices are durable per book; `boo-lj72` is separate work.
The mixed history on the homepage is explicitly labeled as an example, not an app screenshot.

## Scope and checks

This task changes the repository-root `index.html`, public marketing evidence, and its own ticket notes only.
It does not change `web/index.html`, application code, reader plans, or sibling tickets.
Existing bundled fonts, build instructions, and source links remain local or unchanged.
The lower hero image and reader samples load lazily. Every image has explicit dimensions and alternative text.
The comparison stacks vertically on small screens and follows the page's existing cream and sepia palette.
The targeted 390-pixel preview loaded both comparison images with no horizontal overflow.
The targeted 1280-pixel Night preview showed two 399-pixel columns with no horizontal overflow.
These previews used fallback fonts because the preview could not load absolute local font URLs.
The production page still uses its unchanged bundled font files, whose paths passed the asset check.
See `verification.json` for exact commands and the boundary of each check.
Parent integration owns the final full-page browser review and ticket closure.
