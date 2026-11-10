# PDF reflow as the page's own word images

Date: 2026-11-09, revised the same day for the "Tesseract layout first" decision. Epic: boo-fval. Parent: boo-fs0n. Blocked by: boo-pw1d.

## Decision

On 2026-11-09 the user decided that every PDF reflows as word images. Bookfin cuts the printed page into its words and wraps those word images to the screen. The reader sees the real printed words, with their italics, accents, footnote marks and size ratios. The mistakes of text recognition stay hidden, because the reader sees the pixels and not the recognized letters.

- If the PDF's own text layer is usable, word geometry comes from it. Otherwise it comes from Tesseract.
- A switch shows the page's recognized or extracted text in the reader's font instead of the word images. That is the reflow view of today.

Later on 2026-11-09 the user chose "Tesseract layout first" over k2pdfopt as a library:

- Bookfin does not add k2pdfopt. KOReader's libk2pdfopt bundles modified copies of Tesseract, Leptonica and MuPDF. They duplicate what Bookfin already ships (Tesseract, Leptonica and PDFium). Its license is the GNU GPL version 3.
- For a scanned page, Tesseract first runs its layout analysis alone. This layout pass finds blocks, paragraphs, lines and words, and recognizes no letters. The word images show as soon as it ends. Full recognition then runs in the background and fills in the text under the images.
- Until that text arrives, a saved place inside the page resolves to the page itself.
- k2pdfopt's documented options are the checklist of layout rules that Bookfin's own code covers.
- The gain of the layout pass is measured, on the host now (see "The layout pass") and on an emulator in ticket tb-bmmm.

This document decides these things:

- which parts of k2pdfopt Bookfin adopts, as a checklist of its options
- the word geometry model and its two sources
- the layout pass, its native cost and its measured gain
- how the arriving text attaches to the word images
- lines, paragraphs and the regions that stay whole
- rendering, memory, text size and theme tints
- the text under the images: search, selection, copy, read-aloud and places
- the switch to the text view
- the waiting state, page turns, the scrub deck and the scrub bar
- tests, fixtures and the device acceptance
- two open decisions for the user
- the order of work

## Terms

| Term | Meaning |
| --- | --- |
| Reading text | The `PdfText` that `PdfBook.text` gives for a page. Its `source` and `digest` name every saved place on the page. |
| Page unit | The length unit of word geometry. One page unit is the width of the page. The origin is the top left corner, and y grows down. |
| Word | One printed word, with its box on the page in page units. On a text layer page it is a run of the reading text's `source` without white space. On a scanned page the layout pass finds it. |
| Layout pass | Tesseract's page layout analysis alone (`TessBaseAPIAnalyseLayout`), without letter recognition. |
| Layout record | The output of the layout pass for one page: blocks with their types, paragraphs, lines with baselines, and words with boxes and baselines. |
| Text attachment | For each word, its range of the reading text. It is empty until the reading text exists. |
| Line | The words that the source prints on one line, in reading-text order, with the line's baseline. |
| Baseline | The line that the letters of a printed line sit on. A skewed scan has a sloped baseline. |
| Own baseline | The baseline under one word, from the bottoms of its letters that have no descender. |
| Block | A group of lines that the source prints as one column piece. Tesseract gives each block a type, such as text, picture or table. |
| Region | A part of the page that reflow keeps whole: a figure, a table, an equation or a drop cap. |
| Piece | One thing that reflow places on the screen: a word or a region. It has a source rectangle on the page, a target rectangle on the screen, and a range of the reading text. |
| Page analysis | The facts about a page that need its pixels: regions, ink that no word covers, line-end hyphens on scanned pages, and the body line height. |
| Body line height | The median height of the page's prose lines, from the top of the ascenders to the bottom of the descenders, in page units. |
| Column | The reflowed lines of one source page for one column width and one text size. |
| Screen | The lines of a column that show at one time. |
| Band | One rendered strip of the page, at screen resolution, that holds the source rectangles of the pieces of one screen. |
| Word view | Reflow with word images. |
| Text view | Reflow with the reading text in the reader's font. This is the reflow view of today. |

## k2pdfopt and our situation

k2pdfopt is a desktop and e-reader program by Willus. KOReader uses it as the library libk2pdfopt for its reflow of PDF and DjVu pages.

### Its situation

- It was made to make PDF and DjVu files readable on e-ink readers. Its name means "Kindle 2 PDF Optimizer". Its default device is the Kindle 2. That screen has 560 by 735 pixels at 167 dpi, with 4 bits a pixel ([k2pdfopt home], [k2pdfopt options]).
- It finds columns, text rows and words from the white gaps in the page bitmap. It does not use recognition to find words. Its gap and size limits are fractions of the lowercase letter height. Examples are `-ws` for word spacing and `-de` for the size of specks that it ignores ([k2pdfopt options], [bmpregion.c], [textrows.c]).
- Its recognition option (`-ocr`, with Tesseract, GOCR or MuPDF text) only puts an invisible text layer over its output. The options page says that this text does not change the look of the output file ([k2pdfopt options]).
- It can straighten a skewed page by up to 4 degrees with `-as`, which is off by default. Leptonica can de-warp whole pages with `-dw` ([k2pdfopt options]).
- During a wrap, it removes line-end hyphens (`-hy`, on by default). It keeps the source's justification by default (`-j -1`). It does not wrap regions that it judges to be figures, and it fits figures to the device width ([k2pdfopt options], [textrows.c]).
- KOReader renders one reflowed bitmap for a whole source page. It keeps a map from reflowed word boxes to native word boxes, and uses that map for selection, highlights and links. It caches reflowed pages. If memory runs low, it drops half the cache ([koptinterface.lua]).
- k2pdfopt is under the GNU GPL version 3, and its library files under the GNU Affero GPL ([k2pdfopt options], [wrapbmp.c]).
- KOReader's libk2pdfopt bundles modified copies of Tesseract, Leptonica and MuPDF (from the user's decision).
- Its own documentation lists its weak points. Its FAQ says: "my tables / equations / figures get mangled", and its fix is to draw boxes around them. When rows have no clear gap, it "views the region as a graphical block (figure)" ([k2pdfopt FAQ]). On a tilted page, "the wide spacing of the words fools k2pdfopt into thinking there are sub-columns" ([k2pdfopt straighten]).
- Its recognition is optional and off by default. It makes text that can be searched or copied, and it adds time: the OCR page shows 6.8 seconds with Tesseract against 4.5 seconds with GOCR for one conversion ([k2pdfopt OCR]).

### Our situation

- Bookfin runs on a phone such as the Pixel 8. It has a fast CPU, a GPU and a color screen with about 2.6 device pixels per logical pixel.
- Tesseract already runs on every page without a usable text layer. Its layout analysis finds blocks with their types, paragraphs with their justification, lines with their baselines, and words, in Tesseract's reading order. On the host, the layout pass alone takes 13 percent of the time of full recognition on a dense page (see "The layout pass").
- The recognition cache already keeps the hOCR output of every recognized page.
- A born-digital PDF has a text layer with exact boxes for each character.
- Places, search and the reflow view of today depend on the reading text. Its characters must keep their meaning.

### What we adopt and what we leave

Bookfin adds no k2pdfopt code. Its options serve as a checklist of layout rules that our own code covers. The defaults below come from [k2pdfopt options].

| k2pdfopt option or weak point | Its default and meaning | Bookfin's rule | Section |
| --- | --- | --- | --- |
| `-wrap` | On. Wraps word bitmaps to the device. | Wrap word images to the screen. This is the feature. | Wrapping |
| `-j -1` | "Maintain the justification of the document as it is." | Keep each paragraph's justification: justified, left or centered. | Paragraphs |
| `-hy` | On. The option text is "hyphen detection/elimination when wrapping text". | Join a hyphen pair on one line and hide its hyphen. Keep the hyphen at a line end. | Rejoined hyphens |
| `-f2p 0` | Figures "are fit to the width of the device." | Keep regions whole, at the page's scale, and fit them to the column and the screen. | Regions |
| `-jfc` | On. Joins a figure caption to its figure. | A caption stays on the screen of its figure. | Regions |
| `-col 2`, `-cg 0.1` | Detects up to 4 columns (1, 2 or 4), with a minimum column gap of 0.1 inch. | Tesseract's layout pass finds columns on a scanned page. The text layer's order gives them on a born-digital page. A text layer in a bad order goes to recognition. | Word geometry |
| `-as` | Off. When on, straightens a page tilted by up to 4 degrees. | Always on, per line: each word sits on its line's baseline and turns by the line's slope. No limit of 4 degrees. | Baselines |
| `-de 1.0` | Ignores specks smaller than 1 point. | Drop ink specks smaller than a third of the body line height. | Page analysis |
| `-ws -0.20` | Word spacing as a fraction of the lowercase "o" height. Negative means automatic. | The layout pass and the text layer give words. The gap between word images is the source gap, between a third and one body line height. | Wrapping |
| `-vls -1.2` | Line spacing as a fraction of the text size. | Keep the source's baseline pitch, scaled. | Baselines |
| Weak point: tables, equations and figures get mangled. | Its fix is to draw boxes by hand. | Tesseract's block types, the prose line test and the ink analysis make regions that stay whole. | Page analysis, Regions |
| Weak point: wide word spacing reads as sub-columns. | Its fix is to straighten the page or to force the column count. | If wide gaps line up with the wide gaps of a neighbor line, they make a table row. A justified line with wide gaps stays prose. | Page analysis |
| Weak point: tight line spacing reads as a figure. | No fix. | Lines come from the layout pass or the text layer, not from white gaps between rows. | Word geometry |
| One bitmap for each reflowed page (KOReader) | KOReader blits the visible part of a whole reflowed page ([koptinterface.lua]). | Draw pieces from bands with the GPU. Memory follows the screen, not the text size. | Rendering |
| Map reflowed boxes to native boxes (KOReader) | Used for selection, highlights and links ([koptinterface.lua]). | Each piece keeps its source rectangle and its text attachment. | The text under the images |
| De-warp (`-dw`) | Leptonica de-warp of whole pages. | Leave. Tesseract's word baselines follow a curved row. | Baselines |

## Model

```mermaid
flowchart TB
  subgraph Geometry["Word geometry (shown at once)"]
    TL["preparePdfPage (hop)<br/>text layer: characters and boxes"]
    LP["layout pass (native worker)<br/>blocks, paragraphs, lines, words"]
  end
  subgraph Text["Reading text (names every place)"]
    TT["text layer text"]
    HO["full recognition (native worker)<br/>hOCR, then decodeRecognizedPage"]
  end
  TL --> PG["PageGeometry"]
  TL --> TT
  LP --> PG
  HO -->|attachText (hop)| AT["Text attachment<br/>a range for each word"]
  TT --> AT
  PG --> BK["PdfBook<br/>ReflowPage cache"]
  AT --> BK
  BK -->|render at 1600 px| AN["analyzePage (hop)<br/>regions, uncovered ink,<br/>hyphens, body line height"]
  AN --> LY["layoutColumn (hop)<br/>reads geometry and analysis,<br/>never the text"]
  SS["ReaderSession<br/>page view, text size"] --> LY
  LY --> WP["PdfWordPages<br/>column, band images,<br/>shown and next screen"]
  WP -->|renderPart| BK
  WP --> DR["WordScreen painter<br/>drawAtlas with tint"]
  VP["PdfViewport<br/>shown page and place"] --> WP
  VP -->|onAddress| SS
```

Two facts describe a page, and each has one owner:

- The word geometry says where the printed words are. On a text layer page it comes from the character boxes. On a scanned page it comes from the layout pass. It is ready before the text of a scanned page.
- The reading text says what the words are, and it names every saved place. On a text layer page it comes with the geometry, from the same hop. On a scanned page it comes from full recognition, seconds later.

The text attachment joins the two: for each word, its range of the reading text. Everything that the reader sees is derived from the geometry alone. The page analysis comes from the geometry and a render, the column from the analysis and the settings, and the band images from the column. So the arrival of a scanned page's text never moves a word on the screen. It only fills in the attachment, which search, selection, copy, read-aloud and places use.

### Owners

| State | Owner | Changes when |
| --- | --- | --- |
| Reading text | `PdfBook`, with its cache of 16 page texts. `BundledEnglishText` keeps its 16 selected recognized pages, as today. | A page's text is read or recognized. |
| Word geometry of a text layer page | `PdfBook`, beside the page's text, from the same hop. | The page's text layer is read. |
| Layout record of a scanned page | `BundledEnglishText`, which owns the native worker. It keeps the record in the recognition cache on disk, beside the hOCR, under its own key. | The layout pass runs on a page that has no record. |
| Text attachment, and the `ReflowPage` that holds geometry, analysis and attachment | `PdfBook`, in a cache of 16 pages. | The geometry arrives, or the reading text arrives. |
| Page analysis of a page | `PdfBook`, inside the `ReflowPage`. | The word view first needs the page. |
| Body line height of the book in this session | `PdfBook`, beside the analyses. | A page with at least 8 prose lines is analyzed. |
| The page view: original, word view or text view | `ReaderSession`, in one enum that replaces the `reflow` bool. It lasts for the run of the app, as the reflow choice does today (t9-3n2m). | The person chooses a view. |
| Text size | `ReaderSession`, as today. | The person steps the size. |
| Theme | The app's appearance, as today. | The person chooses cream or night. |
| Column of the shown page, its screens, its band images | `PdfWordPages`, one per `PdfViewport`. | The shown page, the column width, the text size or the shown screen changes. |
| Shown page, shown screen and the shown place | `PdfViewport`, as today. | A turn, a jump or a new text. |
| Selection | The selectable of the shown screen. It is ephemeral UI state. | A long press, a handle drag or a new screen. |

## Word geometry

### The payload

`PdfText` does not change, so its digest and every saved place keep their meaning. The geometry is a payload of its own, because on a scanned page it exists before the text. It uses typed lists, so it crosses isolates as blocks.

```dart
/// Where the printed words of a page are. Lengths are in page units: 1.0
/// is the page width, the origin is the top left corner, and y grows down.
/// Words are in reading order: the text layer's order, or Tesseract's.
class PageGeometry {
  /// The page height in page units.
  final double height;

  /// For each word: left, top, right and bottom.
  final Float32List boxes;

  /// For each word: the y of its own baseline at its left and right
  /// edges, or NaN when the source does not know it.
  final Float32List ownBaselines;

  /// For each word: the width of a hyphen that ends it, or 0.
  final Float32List hyphens;

  /// For each line: the index of its first word. One more entry ends the
  /// last line.
  final Int32List lineStarts;

  /// For each line: the y of its baseline at x = 0, its slope, its height
  /// from ascender top to descender bottom, and its descender depth.
  final Float32List lineMetrics;

  /// For each block: the index of its first line, and one more entry.
  final Int32List blockStarts;

  /// For each block: its kind as the source knows it (text, picture,
  /// table or unknown). A text layer knows only text.
  final Uint8List blockKinds;

  /// The lines that start a paragraph in the source, when the source says
  /// so, with the paragraph's justification and first-line indent. Empty
  /// for a text layer.
  final Int32List paragraphStarts;
  final Uint8List paragraphJustifications;
  final Float32List paragraphIndents;
}

/// For each word of a [PageGeometry], its range of [PdfText.source]: the
/// first and the end character. An empty range (start == end) marks a word
/// that names no text, at the place between its neighbors.
typedef TextAttachment = Int32List;
```

`layoutColumn` takes the geometry and the analysis, and never the text or the attachment. So the screens of a page are the same before and after its text arrives.

The invariants of `PageGeometry` and its attachment:

- Every box has a positive area inside the page.
- Lines and blocks cover the words in order.
- Attached ranges are in increasing order and do not overlap.
- No attached range holds white space.

`PageGeometry.checkInvariants` makes sure of all of them, on demand.

### The layout pass

A scanned page gets its geometry from Tesseract's layout pass. It runs on the one native recognition worker, before full recognition of the same page.

What the pinned library offers. These facts come from tesseract4android 4.9.0 as `nix/ocr.nix` pins it, read with `javap` and `nm`, and from its pinned source tarball:

- The Java class `TessBaseAPI` has no call for the layout pass, line baselines, paragraph information or block types. `getWords()` runs the layout pass as a side effect, but it gives only a flat list of word images and boxes.
- Its `libtesseract.so` exports Tesseract's C API: `TessBaseAPIAnalyseLayout`, `TessPageIteratorBoundingBox`, `TessPageIteratorBaseline`, `TessPageIteratorParagraphInfo`, `TessPageIteratorBlockType`, `TessPageIteratorNext` and `TessPageIteratorIsAtBeginningOf`, with `TessBaseAPIRecognize` and `TessBaseAPIGetHOCRText`.
- `TessBaseAPI::AnalyseLayout` finds the lines, makes the page's words without recognition, and runs paragraph detection (`baseapi.cpp`, line 740).
- At the word level, `PageIterator::Baseline` evaluates the row's baseline at the word's left and right edges (`pageiterator.cpp`, line 534). So a word's baseline follows a curved row.
- Table detection is on by default (`textord_tabfind_find_tables`). Equation detection is off (`textord_equation_detect`), and it needs a legacy model that Bookfin does not ship. So equations come from the prose line test.

The native change (ticket tb-t0ea):

- A small C library, `bookfin_ocr`, joins the CMake build that already builds `bookfin_mobi`. It links the AAR's `libtesseract.so` as an imported library and includes `capi.h` from the pinned source tarball. No library is rebuilt, and no new dependency is added.
- `TesseractEngine` in `OcrChannel.kt` moves from the Java `TessBaseAPI` to one C API handle, with the same model, `OEM_LSTM_ONLY` and page segmentation mode 3. One handle keeps one model in memory.
- A new channel method `layout` sets the page image, runs the layout pass, and returns the layout record as one typed list. The engine keeps the image. `recognize` then recognizes that image and returns hOCR, as today.
- Recognition after the layout pass reuses the lines that the layout pass found. The ticket makes sure that its hOCR is the same, byte for byte, as the hOCR of recognition alone. So recognized text and digests do not change.
- The estimated size is about 250 lines of C and Kotlin and one CMake target. One Nix output unpacks the AAR's libraries and the header. It is one ticket for one agent.

The measured gain, on the host. `tool/evidence/reader/layout-pass/20261109/` holds the program and the pages. Tesseract 5.5.3 ran on one thread of the user's Mac with Bookfin's bundled model.

| Page | Layout pass | Full recognition | Recognition after the layout pass | Layout words | hOCR words |
| --- | --- | --- | --- | --- | --- |
| Dense text, 1600 by 2093 pixels | 179 ms | 1341 ms | 1160 ms | 783 | 784 |
| The same page turned by 2.5 degrees | 218 ms | 811 ms | 595 ms | 436 | 442 |
| Raven scan, 1600 by 2595 pixels | 116 ms | 219 ms | 104 ms | 38 | 36 |

- On a dense page, the word images can show after 13 percent of the time that full recognition takes.
- The layout pass and the recognition after it cost about as much as full recognition alone. So the text arrives at about the same time as today.
- The layout pass found the turned page's slope as 2.46 degrees.
- Layout words and hOCR words differ in count. So the text attaches by box overlap, not by index.
- Ticket tb-bmmm measures the same on an Android emulator.

The layout record of a page is small (about 30 KB for 800 words). `BundledEnglishText` keeps it in the recognition cache on disk under its own key: the SHA-256 of `bookfin-layout-1`, the recognition version, the book's digest and the page. So a page opens with its words at once on a later visit. A page that Bookfin recognized before this epic has hOCR but no layout record. It gets one layout pass on its first visit, and its text is already there.

The shown page's layout pass goes to the front of the recognition queue. Its full recognition follows it. Other waiting pages, such as the pages of a search, wait behind both.

### Text attachment

On a text layer page, each word is cut from the reading text, so its range is known at once.

On a scanned page, the arrival of the text starts `attachText(geometry, hocr)` in a hop. `decodeRecognizedPage` builds the same `source` as today, and it also gives each hOCR word's range and box.

1. Each hOCR word joins the layout word whose box overlaps it most. The overlap must cover at least a third of the smaller box.
2. A layout word's range runs from the first character of its first joined hOCR word to the end of its last one.
3. If a layout word's range breaks the increasing order of ranges, it gets an empty range.
4. An hOCR word that joins no layout word adds its characters to the nearest earlier layout word on its line. So search still finds it on the screen.

The recognition cache keeps the hOCR output as it is, and `BundledEnglishText.version` does not change. A new version makes every saved place on a recognized page fail to resolve.

### From the text layer

`preparePdfPage` already receives each character's box in PDF points. It also receives the page width and height, and records:

- each word: a run of `source` without white space, as the reflowed text already splits it. Its range is its attachment.
- the descender set: `g j p q y`, the comma, the semicolon and the like
- its box: the union of its characters' boxes, turned into page units with y flipped
- its own baseline: the median bottom of its characters outside the descender set
- lines: a word starts a new line in two cases. Its height overlaps the previous word's height by less than half the smaller height, or it starts to the left of the previous word. The text is a candidate, so its order is the reading order, and this rule follows it.
- blocks: a line starts a new block in two cases. The vertical gap above it is more than twice the median line pitch. Or its left edge moves by more than a quarter of the page width.
- each line's baseline: the median of its words' own baselines, with a slope of 0
- each word's hyphen: if the word ends a line with a hyphen character, the width of that character's box

### When the geometry is not usable

- A text layer can be a candidate while its boxes are not usable: a character without a finite box of positive area inside the page, or a word whose box spans more than three line heights. Then the page has no geometry. The word view shows that page in the text view, with no notice. Its places keep their meaning, because its reading text does not change.
- A text layer can have usable boxes while its order is not usable (`_textWarning` returns a reason). Then the page's reading text comes from recognition, as today, and its words come from the layout pass. The text layer's boxes are not used. A second design sorts the text layer's words by position into a new reading text. We reject it. That text has a new digest, so every place that a person saved on such a page from the recognized text fails to resolve. Also, Tesseract's layout analysis finds columns better than a sort by position.
- A page whose reading text has no content shows the original page with the quiet line, as today.

## Page analysis

The word view needs facts that only the pixels know. `PdfBook.reflowPage(sourcePage)` gives the page's geometry and page analysis at once. It adds the text attachment after the reading text arrives. It renders the page at 1600 pixels wide, as recognition and the layout pass do, so their boxes match the raster exactly. The analysis runs in a hop. It takes the raster and the geometry, and returns only small typed lists.

1. Ink. If a pixel's luminance is below half, the pixel is ink. The analysis works on a mask that is 4 times smaller in each direction. A 1600 by 2400 raster gives a 400 by 600 mask.
2. Word cover. It removes the ink inside each word box, grown by a fifth of the line height.
3. Components. It joins the remaining ink into 8-connected components. It drops specks smaller than a third of the body line height in both directions, as k2pdfopt's `-de` does.
4. Uncovered ink. Some components lie inside a text line: they overlap the line's height by half, and they are no taller than 1.5 line heights. Each one becomes an extra word of that line, with an empty range. Examples are a mark that the layout pass dropped as noise, and text that a born-digital page draws as shapes. So every printed mark of a line shows.
5. Regions. A block that the layout pass calls a picture or a table is a region. Components close to each other (less than half a body line height apart) join into one region. A word whose box lies more than half inside a region joins the region. Lines that fail the prose line test below join into one region with their neighbors that also fail it.
6. Hyphens. On a scanned page, the analysis finds them from pixels, because the text can arrive later. For each word that ends a line, it looks inward from the word's right edge, within its last 0.6 line heights. A hyphen is the last ink there: a short horizontal mark in the middle of the line's lowercase height, after a white gap. Its width is the distance from that gap to the word's right edge. On a text layer page, the hyphen's character box gives the width, and no pixels are needed.
7. Body line height. The median line height of the page's prose lines.

The prose line test has two parts. First, the line's words share a baseline within a third of the line height. Raised or lowered marks of at most two words are allowed. Second, no gap between its words is larger than 2.5 times the line's median word gap, unless that gap is alone. A neighbor line must have a wide gap that starts and ends within one body line height of it. Only then does the wide gap count. So a table's columns fail the test, and the wide gaps of a justified line do not. This avoids k2pdfopt's weak point of reading wide word spacing as sub-columns. Display equations and table rows fail the test. A line of fewer than 3 words is an exception. If its height is within 1.3 times the block's median line height, it passes. So short headings and last lines pass.

A region is a picture in two cases. The layout pass calls its block a picture, or more than 30 percent of its pixels are mid-tones (luminance between 0.2 and 0.8). Otherwise it is ink, such as an equation, a table or a drop cap. The tint rules below treat the two kinds differently.

## Lines and paragraphs

`layoutColumn(page, settings)` is a pure function. It runs in a hop. Its settings are the column width in logical pixels, the text size in logical pixels after the system text scale, and the device pixel ratio. It returns the column: lines of pieces, each with a source rectangle, a target rectangle, a rotation and a range of the reading text.

### Scale

The scale is the number of logical pixels for one page unit:

```dart
final scale = fontSize * _wordSizeRatio / bodyLineHeight;
```

where

- `fontSize` = the reader's text size in logical pixels after the system text scale, from 14 to 40.
- `_wordSizeRatio` = a named constant that makes a body line at text size 20 look as big as EPUB text at size 20. The device acceptance tunes it once.
- `bodyLineHeight` = a line height in page units. If the page has at least 8 prose lines, it is the page's body line height. Otherwise it is the book's body line height in this session. If the book has no such value yet, it is the page's own value.

Every word and region of a page has the same scale. So headings, footnotes and marks keep their size ratios. A word wider than the column scales down to the column width, alone.

### Wrapping

- Words go into lines in reading-text order, the order of places. If a word fits on the current line, it goes there. Otherwise it starts the next line.
- The gap between two words is their source gap, scaled. It is at least a third and at most one scaled body line height. So the wide gaps of a justified source line do not reach the screen.
- The column has the same margins as the text view: 20 logical pixels on each side.

### Baselines

- Each reflowed line has one baseline. Each word sits so that the point of its source line's baseline under the word's center lands on that reflowed baseline. A skewed line's words then sit level.
- When a word's own baseline is within a quarter of the line height of the line's baseline, the word aligns by its own baseline. This corrects a curved line near the spine. On a scanned page, the own baseline is Tesseract's row baseline at the word's edges. On a text layer page, it comes from the word's letters. A word farther from the line's baseline keeps its offset, so a footnote mark stays raised by its source ratio.
- When a line's slope is more than 0.3 degrees, each of its words rotates by the opposite angle about its baseline point. The source rectangle grows by the rotation's extra width, so no ink is cut.
- The distance between reflowed baselines is the source's median baseline pitch, scaled. If a raised or lowered word needs more room, its line grows.

### Paragraphs

- A paragraph starts at the first line of the page, at each paragraph start of the layout pass, and where the geometry rule says so. The geometry rule applies to both sources. A line starts a paragraph in three cases:
  - The vertical gap above it is more than 1.5 times the block's median line pitch.
  - It is indented by more than half a body line height, and the line before it reached the block's right edge.
  - The line before it ended more than two body line heights short of the block's right edge.
- An indented first line keeps its indent, scaled, but at most three body line heights.
- Some paragraphs have all their lines centered on the block. Each line's left and right margins are both more than one body line height, and they differ by less than one. Such a paragraph stays centered. This covers headings.
- When the layout pass gives a paragraph's justification (left, center or right), the paragraph keeps it. Otherwise the geometry decides. A paragraph whose source lines reach the block's right edge, except its last line, is justified. Its reflowed lines spread their gaps, except its last line. Other paragraphs are left aligned. This follows k2pdfopt's default of keeping the source's justification.
- The space between paragraphs is the source's extra gap, scaled, but at most two lines.

### Rejoined hyphens

A hyphen pair is two words of one paragraph. The first ends a source line, and the geometry gives it a hyphen. The second starts the next source line. The pair comes from the geometry and the analysis, not from the text. So the arrival of a scanned page's text does not change it. This follows k2pdfopt's `-hy`, which also finds hyphens from pixels ([bmpregion.c]).

- When both halves land on one reflowed line, the first half's source rectangle loses the hyphen's width, and the second half follows with no gap. The two halves read as one printed word.
- When the halves land on different reflowed lines, the hyphen shows, as in print.
- The reading text does not change. A hyphen pair is a layout fact only. Search and copy of a split word are a separate bug (tb-a07f).

### Regions

- A region takes the place in the flow of the first word that it holds. A region without words goes before the first line, in reading-text order, that starts below the region's top and overlaps it in width. When there is no such line, it goes at the end of the column.
- A region keeps the page's scale. When it is wider than the column, it scales down to the column width. When it is taller than the screen, it scales down to the screen's height.
- A region stands alone on its lines and is centered.
- A caption stays with its figure, as k2pdfopt's `-jfc` does. A caption is a text block of at most 3 lines. It lies within one body line height above or below a picture region, and it overlaps half the region's width. It reflows as words, centered, right after or before its region. If a region and its caption fit on one screen, no screen splits them.
- A drop cap is an ink region at the start of a paragraph. It is more than 1.8 times the body line height tall, and its right edge touches the paragraph's first word. It keeps the page's scale and floats at the start of the paragraph. The paragraph's first lines get shorter until they pass the drop cap's bottom. A drop cap never holds more than 3 lines.

## Rendering

### Bands

- `PdfWordPages` plans the bands of a screen. For each source line that the screen uses, it takes the union of the source rectangles of the screen's pieces from that line. It joins the rectangles of consecutive source lines into one band.
- A band renders at the scale of the screen in device pixels: `scale * devicePixelRatio` pixels for one page unit. A word image then draws at one source pixel for one device pixel, sharp at every text size.
- `PdfBook.renderPart(sourcePage, pixelsPerPageUnit, area)` renders one area through pdfium's crop render. It is the one place that knows pdfium's crop arguments. A band is at most 4096 by 4096 device pixels. A larger band splits.
- A band's pixels go to `ui.decodeImageFromPixels` from pdfium's own buffer, without a copy in Dart.
- A screen draws with one `Canvas.drawAtlas` call for each band. Each piece is one sprite: its source rectangle in the band and an `RSTransform` with its place, scale and rotation. The layout makes these lists once for each screen, so a frame does no layout work.

### Memory

- Band images exist for at most two screens of a page: the shown screen and the next screen in the direction of the last turn. A screen's bands hold at most twice the screen's device pixels. The pieces of a screen fill the screen, and the bands add only the gaps between words. So the images of a page take at most 4 times the screen's pixels. On a Pixel 8 (1080 by 2400 pixels, 4 bytes each), that is about 42 MB. The bound does not grow with the text size.
- The analysis frees its raster at its end. The geometry and analysis of a page take about 30 KB for 500 words, and `PdfBook` keeps 16 pages.
- When the page, the text size, the column width or the theme's paper changes, `PdfWordPages` disposes the images that the new screens do not use.

### Off the UI isolate

| Work | Where it runs |
| --- | --- |
| Layout pass and recognition | The native recognition worker |
| hOCR decode, text attachment, and text layer prepare with geometry | A hop |
| Analysis raster and band renders | pdfium's worker, through pdfrx |
| Page analysis | A hop |
| Column layout and the sprite lists | A hop |
| Image upload | The engine, through `decodeImageFromPixels` |
| Tint | The GPU, through a color filter |
| Frame | One `drawAtlas` for each band |

The column of a page is small (about 500 pieces of 10 numbers each), so one hop returns it whole. Each hop has a fixed cost. So if a page needs both its analysis and its layout, the two run in one hop.

### Text size

A size step of the reader (2 logical pixels, from 14 to 40) changes `fontSize`, so it changes the scale. `PdfWordPages` lays out the column again in a hop, keeps the shown place, and renders new bands. The old screen stays until the new screen's bands are ready, so no blank frame shows.

### Theme tints

- Word pieces and ink regions use a duotone tint. It maps luminance 0 to the theme's text color (`onSurface`) and luminance 1 to the theme's paper (`surface`). One `ColorFilter.matrix` does this for cream and for night. So night shows light ink on dark paper, and cream shows dark ink on cream paper. Colored ink loses its hue but keeps its lightness.
- Picture regions keep their colors. On cream, they multiply by the paper color, so their white becomes cream. On night, they show at 80 percent brightness and are not inverted, so photographs do not become negatives.

## The text under the images

The word images are only a picture of the reading text. Every text feature uses the reading text through the text attachment.

Before a scanned page's text arrives, its words have empty ranges:

- A saved place inside the page resolves to the page itself. The page opens on its first screen.
- The viewport keeps the saved place as it is, and does not replace it with the start of the page. Engine rule 3 forbids losing a place in a book. A turn inside the page is a real move, and it saves the place as the page itself (character 0).
- The person can turn or touch the page before the text arrives. If they did neither, the viewport then shows the screen that holds the saved place, in one move with no notice. Otherwise the shown screen stays.
- Selection, copy and the search highlight wait for the text. A long press before then does nothing.

The rest of this section describes a page that has its text.

- Search searches `PdfText.text`, as today. A hit opens the screen that holds the hit's first character.
- A place is the first character of the shown screen's first piece with a nonempty range, through `PdfBook.addressFor`. If no piece of the screen has a range yet, the place is the page itself. The representation stays `policy/engine/recognition-or-extracted/digest`. A place saved in the word view opens in the text view at the same character, and the reverse.
- To show a place, the viewport finds the piece whose range holds the place's character, or the first piece after it, and shows its screen. When a turn goes back from a page's first screen, the previous page opens on its last screen.
- Selection: a caret is a character of `source`. A point on a word piece maps to a caret by its share of the piece's width, divided evenly over the piece's characters. A point between pieces maps to the nearest piece edge. A long press selects the word under the finger. The highlight of a range is made of parts of target rectangles. For each piece that the range touches, it is the part that the range covers, by the same even division. A piece with an empty range never gets selected.
- Copy gives `PdfText.text` between the two carets.
- Screen readers read one node for each paragraph, with the paragraph's reading text as its label.
- Read-aloud (epic t0-t799) gets the same two things: the reading text with its places, and the rectangles of a character range on the shown screen. The word view adds no other interface for it.

The selectable follows the EPUB page's selection (`lib/reader/epub/selection.dart`). Both give a caret for a point, the rectangles of a caret range, the text of a caret range and the word at a caret. The selection ticket extracts the Flutter selection event handling that both share into one selectable that takes those four questions. If the shared part turns out to branch on its caller, the ticket keeps two selectables and writes why.

## The switch to the text view

The page view is one choice with three values: original, word view and text view. `ReaderSession` keeps it for the run of the app, as it keeps the reflow choice today (t9-3n2m). It is not saved in the reading records. When the person turns reflow on, the word view shows. The control lives in the Reading settings sheet, which is glass. Open decision 1 decides its shape.

The text view stays the reflow view of today. It uses the reading text in the reader's font. te-rtok (Source Serif 4 for PDF reflow) applies to it.

## Waiting, turns, the scrub deck and the scrub bar

- Waiting for words. On a text layer page, the word view waits for the reading text, as boo-pw1d leaves it. On a scanned page, it waits for the layout record, from the disk cache or from the layout pass, and not for recognition. Then it waits for the page analysis, the column and the first screen's bands. During all of these, the original page shows under the thin progress line of today. One waiting flag in `PdfViewport` covers them. When the first screen is ready, it replaces the original page with no notice.
- Waiting for text. While full recognition of the shown scanned page runs, the thin progress line stays over the word images. The text's attachment removes it. The screen does not change.
- Failure. The layout pass, the analysis or a band render can fail. If its text exists, the page then shows in the text view. Otherwise the original page shows under the progress line until its text arrives. If recognition fails after the words show, the words stay, the progress line goes, and selection and search stay unavailable on that page. If the text fails on a text layer page, the quiet line of today shows over the original page.
- Turns. A swipe or a screen reader's scroll action turns as open decision 2 decides. The band images of the next screen render after the shown screen's bands. So a turn inside a page shows its screen in the next frame.
- Neighbor pages. The word view prepares no other source page. It starts no layout pass and no recognition for a page that is not shown.
- The scrub deck shows the original pages, as today. It starts no layout pass, no recognition and no analysis. A scrub lands on the first screen of its page.
- The scrub bar counts source pages, as today. t6-1luw (the bar's spoken value at the end of a page) stays a separate bug.

## Tests

### Fixtures

All fixtures go in `test/reader/fixtures/reflow/`, with a README that records each source and its license.

| Fixture | What it holds | Source |
| --- | --- | --- |
| `scanned-page.pdf`, `scanned-page.layout` and `scanned-page.hocr` | One scanned page of a public-domain book, with italics, a footnote mark, a line-end hyphen, an indented paragraph and a figure with a caption. The layout record and the hOCR come from Bookfin's Tesseract on an Android emulator. | A page of the 1873 "The Raven" scan already in `tool/research/readers/evidence/text-quality/`, or another public-domain scan with those features |
| `equation-page.pdf` | A born-digital page. It has a centered heading, two paragraphs, and an inline formula with a superscript. It also has a display equation, a small table, and a justified paragraph with wide word gaps. | Made in the dev shell with Typst from a source file kept beside it |
| `skewed-page.pdf`, `skewed-page.layout` and `skewed-page.hocr` | The scanned page turned by 2.5 degrees, with a light speck noise. The layout record and the hOCR come from the emulator. | Made in the dev shell from the scanned page |

### Behavior tests

Geometry:

- The layout pass of the scanned page gives its blocks, lines and words in Tesseract's order (native test).
- The skewed page's lines have a slope of 2.5 degrees within 0.2 (native test).
- Recognition after the layout pass gives the same hOCR, byte for byte, as recognition alone (native test).
- A recognized page gives the same reading text and digest as before this epic, so a place saved before it still resolves.
- Each layout word of a recognized page attaches to the characters of the hOCR words that overlap it, in increasing order.
- A layout record saved on disk opens the page's words with no layout pass.
- Each word of a text layer page is a run of the text without white space, and its box holds its characters' boxes.
- A text layer with unusable boxes gives no geometry, and the word view shows that page as text.
- A page whose text layer cannot be put in reading order takes its words from recognition.

Layout:

- Words wrap in reading-text order, and no line is wider than the column.
- On the skewed page, the words of each reflowed line share one baseline within one device pixel.
- A raised footnote mark stays raised by its source ratio.
- A paragraph starts a new line and keeps its indent. A centered heading stays centered. A justified paragraph is justified, except its last line.
- A hyphen pair on one reflowed line draws no hyphen and no gap. A hyphen pair across two reflowed lines draws the hyphen.
- The display equation and the table of the equation page each show as one region, scaled to fit the column. Search still finds their text.
- Ink that no word covers still shows, in its line.
- A justified line with wide word gaps stays prose, and a table's aligned gaps make a region.
- A figure's caption shows on the same screen as the figure.
- The screens of a scanned page are the same before and after its text attaches.

Rendering:

- A word image draws at one band pixel for one device pixel.
- One text size step up makes a body word 10 percent taller at size 20.
- A black pixel draws in the theme's text color, and a white pixel in the theme's paper, in cream and in night.
- The live band images never hold more than 4 times the screen's pixels.
- Analysis and layout run through the injected hop.

Places and text:

- The place of a shown screen is its first word. A book reopened at that place shows the same first word.
- A place saved in the text view opens in the word view on the screen that holds it, and the reverse.
- A long press selects the word under the finger. Copy gives the reading text of the selection.
- A search hit opens the screen that holds the hit.

The view and the reader:

- The page view choice lasts through closing and opening books in one run, and a new run starts on the original page.
- On a scanned page, the first word screen shows after the layout pass, before recognition ends. The progress line stays until the text attaches.
- Before the text attaches, a saved place inside the page opens the page's first screen and is not overwritten. When the text attaches and the person has not turned, the screen that holds the place shows.
- A long press before the text attaches selects nothing.
- The shown page's layout pass runs before the waiting recognition of other pages.
- A turn past a page's last screen shows the next page's first screen. A turn back from a page's first screen shows the previous page's last screen.
- The scrub deck shows original pages and starts no layout pass and no recognition.

Each module with state keeps one `checkInvariants`:

- `PageGeometry`, as above.
- The page analysis cache of `PdfBook`: at most 16 pages, each with the digest of its reading text.
- `PdfWordPages`: its images belong to the shown or the next screen, and their pixels are within the bound.

### Device acceptance

On the Pixel 8 or an emulator through the T3 device tools:

- Open the three fixtures and one scanned book from the user's library. Take screenshots of the word view in cream and in night, at text sizes 14, 20 and 40, and of the text view.
- Measure the time from a turn to a new source page with cached text to its first screen. The target is 400 ms on the Pixel 8.
- Measure the time from a turn to a scanned page that was never recognized to its first word screen, and to its text. Compare them with the time to the first text screen before this epic.
- Measure the graphics memory of the reader with `dumpsys meminfo` while the person turns ten screens.
- Make sure that a turn inside a page drops no frame, with the frame timing overlay.
- Tune `_wordSizeRatio` once against an EPUB at size 20.

## Open decisions

### Decision 1: the shape of the switch

| Design | Control | Cost |
| --- | --- | --- |
| A: three views in one choice | The Pages row in Reading settings has three segments: Original, Page words, Text. | One control, one tap to any view. Three segments are narrower on a small phone at a large system text size. |
| B: a second row under Reflow | The Pages row keeps Original and Reflow. A second row, "Reflow shows", with Page words and Text, shows only while Reflow is on. | The first row stays as today. The text view is two steps away, and the sheet grows by one row in reflow. |

Usage of A: the person opens Reading settings and taps Text. Usage of B: the person opens Reading settings, taps Reflow, then taps Text in the second row.

Both designs keep these things:

- one enum of three values in `ReaderSession`
- the same lifetime, until the app restarts
- the same glass sheet
- the word view as the view that reflow shows first

### Decision 2: how a page turns inside a source page

| Design | Turn | Cost |
| --- | --- | --- |
| A: screens of whole lines | The column of a source page cuts into screens at line boundaries. A swipe shows the next screen. A vertical drag does nothing. | Matches the EPUB reader's pages and the shared gesture model. No line is ever cut at the screen's edge. The last screen of each source page is often part empty. The text view also needs whole-line screens, which is one more ticket. |
| B: one scroll column for each source page | As the text view does today: a vertical drag scrolls, and a swipe moves 85 percent of the screen, snapped to a line boundary. | The text view does not change. Bands must render ahead of a fast drag, so a fast drag can show empty lines for a moment. Free scrolling cuts lines at the screen's edges. |

Usage of A: the person swipes left three times through a long source page, and the fourth swipe opens the next source page. Usage of B: the person drags up through the page, or swipes, and at the bottom a swipe opens the next source page.

Both designs keep places, the waiting state, the scrub bar and the deck as described above, and both keep a screen's next bands ready.

## Order of work

Ticket keys W0 to W10 name the tickets. The table maps each key to its ticket id.

| Key | Ticket | Work | After |
| --- | --- | --- | --- |
| W0 | tb-t0ea | The layout pass on Android through Tesseract's C API, and one native handle | boo-pw1d |
| W0b | tb-bmmm | Measure the layout pass against full recognition on an emulator | W0 |
| W1 | tb-jidt | Scanned page geometry from the layout record, its disk cache, text attachment from hOCR, and the scanned and skewed fixtures | W0 |
| W2 | tb-xwlj | Word geometry from the text layer, and the equation fixture | W1 |
| W3 | tb-t8rh | Page analysis and `PdfBook.reflowPage` | W2 |
| W4 | tb-0mex | Column layout: wrap, baselines, paragraphs, hyphens, regions, captions, screens | W3, decision 2 |
| W5 | tb-xjfi | Bands, `drawAtlas`, tints and the memory bound in `PdfWordPages` | W4 |
| W6 | tb-22fu | The word view in `PdfViewport`: waiting for words and for text, places, turns, failure | W5 |
| W7 | tb-9mcf | The page view choice in the session and the settings switch | W6, decision 1 |
| W8 | tb-mfkk | Selection, copy, search hits and screen reader nodes on word images | W6 |
| W9 | tb-fi98 | Drop caps | W6 |
| W10 | tb-fb6j | Device acceptance and tuning | W0b, W7, W8, W9 |

If the user picks design A of decision 2, W6 also cuts the text view into whole-line screens.

## Sources

- [k2pdfopt home]: https://www.willus.com/k2pdfopt/
- [k2pdfopt options]: https://www.willus.com/k2pdfopt/help/options.shtml
- [k2pdfopt FAQ]: https://www.willus.com/k2pdfopt/help/faq.shtml
- [k2pdfopt straighten]: https://www.willus.com/k2pdfopt/help/straighten.shtml
- [k2pdfopt OCR]: https://www.willus.com/k2pdfopt/help/ocr.shtml
- [bmpregion.c]: https://raw.githubusercontent.com/koreader/libk2pdfopt/master/k2pdfoptlib/bmpregion.c
- [textrows.c]: https://raw.githubusercontent.com/koreader/libk2pdfopt/master/k2pdfoptlib/textrows.c
- [wrapbmp.c]: https://raw.githubusercontent.com/koreader/libk2pdfopt/master/k2pdfoptlib/wrapbmp.c
- [koptinterface.lua]: https://raw.githubusercontent.com/koreader/koreader/master/frontend/document/koptinterface.lua
- tesseract4android 4.9.0, as `nix/ocr.nix` pins it: the AAR's `classes.jar` (read with `javap`), its `jni/arm64-v8a/libtesseract.so` (read with `nm -D`), and its source tarball: `src/src/api/baseapi.cpp`, `src/src/ccmain/pageiterator.cpp`, `src/src/textord/colfind.cpp`, `src/src/ccmain/tesseractclass.cpp`, `src/include/tesseract/capi.h`
- The host measurement of the layout pass: `tool/evidence/reader/layout-pass/20261109/`
- Bookfin's recorded hOCR shape: `tool/evidence/reader/integrated/20261103/android/ocr-cache-readback.json`
- pdfium's character boxes through pdfrx 0.9.0: `FPDFText_GetCharBox` in `pdfrx_engine/lib/src/native/pdfrx_pdfium.dart`
