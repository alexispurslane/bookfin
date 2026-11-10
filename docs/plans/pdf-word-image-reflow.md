# PDF reflow as the page's own word images

Date: 2026-11-09, revised the same day for the "Tesseract layout first" decision, and on 2026-11-10 for the user's two product decisions and for trimmed margins. Epic: boo-fval. Parent: boo-fs0n. Blocked by: boo-pw1d.

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
- the shape of the switch and how a page turns, which the user decided on 2026-11-10
- trimmed margins: one crop for the whole book in the Original view, and no running headers or folios in the word view
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
| Page analysis | The facts about a page that need its pixels: regions, ink that no word covers, raised marks and line-end hyphens on scanned pages, and the body line height. |
| Body line height | The median height of the page's prose lines, from the top of the ascenders to the bottom of the descenders, in page units. |
| Column | The reflowed lines of one source page for one column width and one text size. |
| Screen | The whole lines of a column that show at one time. A swipe shows the next screen. |
| Running header | A line near the top or bottom edge of a page that repeats on many pages, such as the book's or the chapter's title. A running footer is the same at the bottom. |
| Folio | A printed page number. |
| Content box | The rectangle around a page's text and figures, without empty margins, running headers and folios, in page units. |
| Side | Left-hand or right-hand pages. A printed book sets their margins as mirror images. |
| Book profile | What the survey learns from a sample of the book's pages: the header and folio templates, and one box for each side. |
| Crop | The part of a page that the Original view shows: the union of its side's box and its content box. |
| Survey | The background work that analyzes every page of a book once, for the book profile and the crops. |
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
| `-de 1.0` | Ignores specks smaller than 1 point. | Drop ink specks smaller than a sixth of the page's median line height. | Page analysis |
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
  BK -->|render at 1600 px| AN["analyzePage (hop)<br/>reflow geometry, regions,<br/>hyphens, body line height"]
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
| Body line height of the book in this session | `PdfBook`, beside the analyses: the median of the body line heights of its analyzed pages with at least 8 prose lines. | A page with at least 8 prose lines is analyzed. |
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

  /// For each block: left, top, right and bottom. A picture block has no
  /// lines, so only its box says where it is.
  final Float32List blockBoxes;

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
- No attached range starts or ends with white space. A range can hold a space inside it, when a layout word joins two hOCR words (rule 2 of "Text attachment").

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

Ticket tb-xwlj built this in `pageGeometryFromCharacters` (`lib/reader/page_geometry.dart`), called from `preparePdfPage`. It changed three rules after it read pdfium's output for the equation fixture:

- pdfium joins the two halves of a word that a hyphen splits at a line end. It removes the line break and puts U+0002 in place of the hyphen, as in `accel\u0002erations`. So a word also ends after U+0002, and U+0002 counts as a hyphen character. The reading text keeps U+0002, so its digest does not change. A word that is only a hyphen is a dash and gets no hyphen width.
- pdfium puts a line break between a letter and its raised mark, such as the 2 of v². The mark's height overlaps the letter's height by about a fifth. So the line rule is: a word starts a new line when it starts to the left of the previous word's left edge, or when its height does not overlap the height of its line so far.
- The vertical gap above a line, for the block rule, is the space between the previous line's lowest descender and this line's highest ascender. The line pitch is the distance between consecutive baselines.

The boxes are page coordinates relative to the page's bounding box, as pdfrx gives them. A page that its PDF rotates can have boxes outside the page's turned width and height. Such a page gets no geometry.

### When the geometry is not usable

- A text layer can be a candidate while its boxes are not usable: a character without a finite box of positive area inside the page, or a word whose box spans more than three line heights. Then the page has no geometry. The word view shows that page in the text view, with no notice. Its places keep their meaning, because its reading text does not change.
- A text layer can have usable boxes while its order is not usable (`_textWarning` returns a reason). Then the page's reading text comes from recognition, as today, and its words come from the layout pass. The text layer's boxes are not used. A second design sorts the text layer's words by position into a new reading text. We reject it. That text has a new digest, so every place that a person saved on such a page from the recognized text fails to resolve. Also, Tesseract's layout analysis finds columns better than a sort by position.
- A page whose reading text has no content shows the original page with the quiet line, as today.

## Page analysis

The word view needs facts that only the pixels know. `PdfBook.reflowPage(sourcePage)` gives the page's geometry and page analysis at once. It adds the text attachment after the reading text arrives. It renders the page at 1600 pixels wide, as recognition and the layout pass do, so their boxes match the raster exactly. The analysis runs in a hop. It takes the raster and the geometry, and returns only small typed lists.

1. Ink. If a pixel's luminance is below half of the paper's luminance, the pixel is ink. The paper's luminance is the value that 90 percent of the page's pixels do not exceed.
2. Raised marks. On a scanned page, ink at a word's right end can lie after a white gap and wholly more than a third of the line height above the baseline. That ink is a footnote mark or a closing quote. It becomes an extra word of the line, with an empty range, and the word's box ends before it. A mark smaller than a sixth of the line height in both directions is a speck and stays in its word.
3. Hyphens. On a scanned page, the analysis finds them from pixels, because the text can arrive later. For each word that ends a line, it looks inward from the word's right edge, within its last 0.6 line heights. A hyphen is the last ink there: ink columns that together stay within a band a sixth of the line height thick. They follow a white column, or a column whose ink leaves the band, such as the stem of a letter that the hyphen touches. The band is at least 1.5 times as wide as it is thick and at most half a line height wide. Its middle lies between 0.1 and 0.3 line heights above the baseline. The hyphen's width runs from its first ink column to the word's right edge. A word that is only a hyphen is a dash. On a text layer page, the hyphen's character box gives the width, and no pixels are needed.
4. Word cover. It covers the pixels inside each word box, grown by a fifth of the line height up and down and by a twentieth to the sides.
5. Components. The ink that no word covers makes a mask that is 4 times smaller in each direction: a cell is ink when any of its pixels is. A 1600 by 2400 raster gives a 400 by 600 mask. The mask's 8-connected components keep the exact pixel box of their ink. Specks smaller than a sixth of the page's median line height in both directions are dropped, as k2pdfopt's `-de` does.
6. Uncovered ink. Some components lie inside a text line: they overlap the line's height by half of their own height, they are no taller than 1.5 line heights, and they lie within one line height of the line's ends. Each one becomes an extra word of that line, with an empty range. Components of one line less than a fifth of its height apart become one extra word. Examples are a mark that the layout pass dropped as noise, and text that a born-digital page draws as shapes. So every printed mark of a line shows.
7. Regions. A block that the layout pass calls a picture or a table is a region. Each other component is a region. Lines that fail the prose line test below join into one region with their neighbor lines that also fail it. Regions less than half of the page's median line height apart join. A word whose box lies more than half inside a region joins the region, and the region grows to hold it.
8. Body line height. The median line height of the page's prose lines. A prose line passes the prose line test and holds no word of a region. A page without prose lines takes the median of all its lines, and a page without lines takes 12/432 of the page width (a 12 point line on a page 6 inches wide).
9. Running headers and folios. With the book profile, the analysis marks the lines near the top and bottom edges that match its templates (see "Trimmed margins"). `RunningTemplates.mark` does this after `analyzePage`, because the templates and a scanned page's text can arrive after the analysis.
10. Content box. The union of the page's words, regions and uncovered ink, without the marked lines and without scan edges. A scan edge is a region that touches an edge of the page, runs along more than half of that edge and is thinner than the body line height, such as the dark bottom edge of the Raven scan.

Steps 2 to 7 use the page's median line height of all lines where they need a page-wide length, because the body line height needs the prose line test, which comes later.

The prose line test has two parts. First, the line's words share a baseline. A word is raised when its box's bottom is more than a third of the line height above the baseline. It is lowered when its own baseline is more than a third below it. A line of 10 or more words can have two such words, and a shorter line one. Second, no wide gap between its source words lines up with a wide gap of a neighbor line. A gap is wide when it is more than 2.5 times the page's median word gap. Two wide gaps line up when they overlap by at least the median word gap. A neighbor line is the line before or after it, with its baseline within two line heights. So a table's columns fail the test, and the wide gaps of a justified line or of a running header do not. This avoids k2pdfopt's weak point of reading wide word spacing as sub-columns. Display equations and table rows fail the test. A line of fewer than 3 words is not held to the first part. It fails when it is more than 1.5 times the height of its block's median line.

A region is a picture in two cases. The layout pass calls its block a picture, or more than 30 percent of the pixels of its box, grown by a fifth of the median line height, are mid-tones (luminance between 0.2 and 0.8 of the paper's). Otherwise it is ink, such as an equation, a table or a drop cap. The tint rules below treat the two kinds differently.

### The analysis's payload

`analyzePage` (`lib/reader/page_analysis.dart`) returns the page's reflow geometry and its `PageAnalysis`. The reflow geometry is the page's word geometry with the extra words of steps 2 and 6 inserted in their lines, in order of position. On a scanned page, it also has the hyphens and the shorter word boxes of steps 2 and 3. Lines, blocks and paragraphs do not change. So `layoutColumn` reads one list of words, and an extra word is a word with an empty range.

`PageAnalysis` holds, in page units:

- each region's box and kind (picture or ink)
- for each word of the reflow geometry, the region that holds it, or -1
- for each word of the reflow geometry, its word in the page's geometry, or -1 for an extra word
- for each line, whether it is a prose line
- the page's body line height

Its `checkInvariants` makes sure that the lists fit the geometry, that region boxes lie inside the page, hold their words and do not overlap, and that a prose line holds no word of a region. The extra words and the region membership add about 5 KB to a page of 500 words.

`PdfBook.reflowPage(sourcePage)` gives a `ReflowPage`: the reflow geometry, the analysis, the line height that scales the page, and `attachedText()`. The line height is the page's body line height when it has at least 8 prose lines. Otherwise it is the book's body line height in this session: the median of the body line heights of the pages with at least 8 prose lines that the book analyzed. Until such a page exists, it is the page's own. `attachedText()` asks for the reading text on its first call, so the analysis alone starts no recognition. It maps the page's text attachment to the reflow words. An extra word gets an empty range at the end of the range before it. `PdfBook` keeps the last 16 reflow pages that it gave, and a kept page is not drawn or analyzed again. A page without geometry, or whose analysis failed, is not kept, so the next request tries again.

### Tuning on the fixtures

Ticket tb-t8rh tuned the first values of this section on the reflow fixtures. The values above are the tuned values. These changes have reasons:

| Rule | First value | Tuned value | Reason |
| --- | --- | --- | --- |
| Ink | Luminance below half of white | Below half of the paper's luminance | The paper of the Raven scan has a luminance of about 0.6. With white as the reference, its paper counts as mid-tones, so every region on the page is a picture. |
| Raised marks | Not a step | Step 2 | On Gibbon's page, the layout words of "field", "city.", "pusillanimous", "Tongres," and "lake." hold footnote marks 17 to 21 inside their boxes, 2 to 5 pixels after a white gap. The word cover alone never uncovers them. |
| Specks | Smaller than a third of the body line height | Smaller than a sixth of the median line height | Mark 18 on Gibbon's page is 11 pixels tall in a line 50 pixels tall: 0.22 line heights. A one-digit mark is as tall and narrower. The specks of the skewed page are at most 2.2 pixels. |
| Word cover | Grown by a fifth of the line height | A fifth up and down, a twentieth to the sides | A mark that the layout pass dropped can sit a few pixels after its word. The mask's cells are 4 pixels wide, so the cover works on pixels before the mask, and a component keeps the exact box of its ink. |
| Wide gap | More than 2.5 times the line's median word gap | More than 2.5 times the page's median word gap | A table row has as many column gaps as gaps inside its cells, so its median gap is itself wide. On the equation page, the table's column gaps are 3.0 to 5.8 times the page's median gap, and the widest gap of the justified paragraph is 1.5 times. |
| Lined-up gaps | Start and end within one body line height | Overlap by at least the median word gap | A column of left-aligned cells ends its gaps at one place, but starts them at the ends of cells of different widths. |
| Raised words | At most two | Two in a line of at least 10 words, otherwise one | The display equation of the equation page has two raised marks among 7 words, so it passed the first rule. A prose line of the fixtures has at most one raised word. |
| Short lines | Pass within 1.3 times the block's median line height | Fail beyond 1.5 times; the gap rule also applies | The heading "Falling Bodies" is 1.35 times the height of its block's lines. A two-column table without rules has rows of two words. |
| Failing lines | Join with their neighbors that fail | The same, with the next line's top within two line heights | The rows of a table without rules are farther apart than half a line height. |
| Hyphens | Short horizontal mark after a white gap | The band rule of step 3 | The hyphen of "Thu-" touches its "u", and the hyphen of "justi-" is 9 by 5 pixels. A middle up to 0.3 line heights leaves out the arm of an r. |
| Mid-tones | Of the region's pixels | Of the pixels of its box grown by a fifth of the median line height | The soft edges of the rule above Gibbon's footnotes, and of the Raven folio, fill their tight boxes. |

What the analysis finds on the fixtures:

| Fixture | Regions | Extra words | Hyphens from pixels |
| --- | --- | --- | --- |
| Equation page | The table (13 words) and the display equation (7 words), both ink | None | None (the text layer gives "accel-") |
| Gibbon's page | The rule above the footnotes, ink | Marks 17 to 21, and the closing quote of "est." | All 10: arse-, num-, es-, Tou-, pro-, en-, ascer-, justi-, tran-, Thu- |
| Raven page | The engraving (a picture block that also holds the title), the pencil page number and the scan's dark bottom edge as pictures, the folio as ink | None | None |

On Gibbon's page, all 43 lines are prose lines, and the body line height is 50 pixels at 1600 pixels wide. The analysis takes about 90 ms on the host for Gibbon's page, with the render and a hop through `Isolate.run`.

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

- The column leaves out the lines that the analysis marks as running headers or folios. Their text stays in the reading text, so search still finds it. A place inside such a line resolves to the first shown piece after it.
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

The page view is one choice with three values: original, word view and text view. `ReaderSession` keeps it for the run of the app, as it keeps the reflow choice today (t9-3n2m). It is not saved in the reading records. The control lives in the Reading settings sheet, which is glass. Its shape is decision 1, which the user settled on 2026-11-10:

- The Pages row has three segments: Original, Page words and Text. One tap chooses any view.
- Page words is the reflow view that the person sees first, because every PDF reflows as word images.
- The row is the shared `PillChoice`. So the fix for large text sizes below serves every pill choice of the app, such as the Theme row (UI rule 2).

At a large system text size, the three segments can be wider than the sheet. `PillChoice` then changes its form in two steps, and never cuts a label:

1. It hides the segments' icons, and keeps the full labels.
2. If the labels still do not fit, the segments stack in a column, one under another, in the same pill shape. Each segment keeps a touch target of at least 48 by 48 logical pixels.

The labels stay whole words, so a screen reader and a person at a large text size read the same names.

The text view uses the reading text in the reader's font, as the reflow view of today does. It changes from one scroll column to screens of whole lines, as the word view does (see "Screens and turns"). te-rtok (Source Serif 4 for PDF reflow) applies to it.

## Waiting, turns, the scrub deck and the scrub bar

- Waiting for words. On a text layer page, the word view waits for the reading text, as boo-pw1d leaves it. On a scanned page, it waits for the layout record, from the disk cache or from the layout pass, and not for recognition. Then it waits for the page analysis, the column and the first screen's bands. During all of these, the original page shows under the thin progress line of today. One waiting flag in `PdfViewport` covers them. When the first screen is ready, it replaces the original page with no notice.
- Waiting for text. While full recognition of the shown scanned page runs, the thin progress line stays over the word images. The text's attachment removes it. The screen does not change.
- Failure. The layout pass, the analysis or a band render can fail. If its text exists, the page then shows in the text view. Otherwise the original page shows under the progress line until its text arrives. If recognition fails after the words show, the words stay, the progress line goes, and selection and search stay unavailable on that page. If the text fails on a text layer page, the quiet line of today shows over the original page.
- Turns. A swipe or a screen reader's scroll action shows the next or the previous screen, as "Screens and turns" says. The band images of the next screen render after the shown screen's bands. So a turn inside a page shows its screen in the next frame.
- Neighbor pages. The word view prepares no column and no bands for another source page, and starts no recognition for a page that is not shown. The survey of "Trimmed margins" runs layout passes for other pages, at the lowest priority.
- The scrub deck shows the original pages. If a page's crop is known, its card is cropped. It starts no layout pass, no recognition and no analysis, and never waits for a crop. A scrub lands on the first screen of its page.
- The scrub bar counts source pages, as today. t6-1luw (the bar's spoken value at the end of a page) stays a separate bug.

### Screens and turns

Decision 2, which the user settled on 2026-11-10: a reflowed source page is cut into screens of whole lines, and a swipe shows the next screen, as in the EPUB reader. The word view and the text view both work this way.

- One rule cuts both views. `cutScreens(lineTops, lineBottoms, keepWithNext, screenHeight)` is a pure function. The word view gives it the lines of its column. The text view gives it the line metrics of its `TextPainter`. It returns the index of each screen's first line. This is the second real use, so the rule is one shared function (Muratori's rule of two).
- A screen holds every line that fits whole below the screen's first line. No line is ever cut at the screen's edge.
- A paragraph gap at the top of a screen is dropped, so a screen never starts with empty space.
- A line can be marked keep-with-next. If it and the next line fit on one screen, they stay on the same screen. A region and its caption use this mark.
- A region taller than the screen already scaled down to the screen's height, so it always fits on one screen.
- The last screen of a source page is often part empty. The next source page starts on a new screen, because each source page has its own place and its own text.
- A swipe forward on a page's last screen shows the next source page's first screen. A swipe back on a page's first screen shows the previous source page's last screen.
- A vertical drag does nothing in either view, as in the EPUB reader. A screen reader's scroll actions turn screens.
- The text view draws one screen as the part of its `TextPainter` from the screen's first line top to the next screen's first line top. It needs no scroll controller.
- The place of a text view screen is the first character of its first line. A change of text size or width cuts the screens again and shows the screen that holds the shown place.

## Trimmed margins

On 2026-11-10 the user asked that the Original view, too, crops away the margins, the running header and the folio, so only the content shows. The user decided two parts of it:

- One crop for the whole book, not one for each page: one box for left-hand pages and one for right-hand pages. So text keeps the same size and place on every page.
- A "Trim margins" switch in the glass Reading settings sheet, on by default. Off shows the full printed page.

### One model for both views

`PdfBook` owns a content box for each page. The page analysis of the word view produces it (steps 9 and 10 of "Page analysis"). So the Original view and the word view agree about what is content: both leave out the same running headers and folios. Cropping in the Original view does not need the word view's layout, bands or screens.

### Running headers and folios

A running header is found by repetition across pages, not by its place alone. The template finder looks at the first and last two lines of each analyzed page, within 12 percent of the page height from the edge. Only text lines count. A region, such as a figure, is never a header.

- Text signature. On a page with a reading text, a line's signature is its text in lowercase. Runs of white space become one space, and each digit becomes `#`. Some signatures repeat at the same place on at least 3 pages within 20 source pages. The same place means a center within half a body line height and half the width shared. Such a signature is a running header. This finds a chapter title that repeats only through its chapter.
- Folio. Some lines hold only a number, arabic or roman. If the number minus the source page number stays the same on at least 3 analyzed pages, the line is a folio. A book's page numbers rise by one per page, so this finds them, also where the header text changes.
- Geometry signature. A scanned page whose text has not arrived has only its layout record. Its edge lines are compared by place and size. An edge line can repeat its center within half a body line height and its height within a quarter. If it does so on at least 30 percent of the body pages of its side, it is a running header or folio.

Footnotes do not repeat at one place with one text, so they stay content. A chapter title at the top of a chapter's first page does not match a template, so it stays too. The templates become part of the book profile, so a single page's analysis can mark its own headers without its neighbors.

Ticket tb-z9h5 built the template finder and the marks (`lib/reader/running_lines.dart`), and the content box (`PageAnalysis.contentBox`). It tuned these rules on `margins-book.pdf` and on a scanned copy of it without text:

| Rule | Value of the design | Built value | Reason |
| --- | --- | --- | --- |
| Edge lines | The first and last two lines | The two highest and two lowest text lines by the middle of their box | The layout pass gives lines in its reading order. On Gibbon's page, the side note "A.D. 491." is the 26th line of 43, in the middle of the page. |
| The same place | Middles within half a body line height, half the width shared | The same, and heights that differ by at most a quarter | The chapter title at the top of a chapter's first page has the words of its running header. On the fixture book it is 1.9 times as tall. |
| Geometry signature | Place and size repeat on 30 percent of the side's body pages | The same, on at least 3 pages, for lines that stand apart from the text | Without the gap rule, the first line of prose of each fixture page was marked. Its middle lies 11 percent of the page height from the top, at the same place on every page. A line stands apart when a white gap of at least 0.75 body line heights lies between it and every other line that shares some of its width. The fixture's headers have gaps of 1.6 body line heights, and Gibbon's header 1.0. |
| Scan edges | Not in the design | Left out of the content box | The Raven scan's dark bottom edge is a picture region. With it, the content box reached the page's bottom edge. |

The marks are `PageAnalysis.runningLines`. `analyzePage` marks none, and `RunningTemplates.mark` gives the analysis with its marks. The content box is derived from the analysis and the reflow geometry when it is asked for, so it cannot fall out of step with the marks.

Known limits for ticket tb-lnak:

- A chapter's running header repeats only through its chapter. If the survey's sample has fewer than 3 pages of a chapter within 20 source pages, that header gets no text template, and its pages keep it as content.
- On a page with text, only the text and folio templates apply, not the geometry templates.
- Regions are never running lines. So the Raven scan's pencil page number in the top margin, a picture region, stays in the content box.

### The book crop

The survey freezes the book profile from a sample of body pages. Outlier pages are left out of the statistics, so they cannot inflate the boxes:

- A blank page has no ink.
- A cover, a title page or a section break has fewer than 5 text lines.
- A plate is more than half picture.

For each side, the box starts at the 5th percentile of the body pages' left and top content edges. It ends at the 95th percentile of their right and bottom edges. It is padded by half a body line height on each side. The padding keeps a small white edge around the text, and it absorbs small differences between pages.

- Each page's crop is the union of its side's box and its own content box. So a body page shows its side's box. A page whose content reaches outside it, such as a wide table, a figure in the margin or a cover, grows its own crop. No content is ever cut.
- Sides come from the parity of the source page number. An inserted plate in a scan can flip the parity for the rest of the book. So if only the other side's box holds a page's content, the page takes that box.
- A blank page shows its side's box.

### The survey

`PdfBook` runs the survey in the background as a data source that owns its cache and its refresh (engine rule 2).

- Order. First the shown page and the next page in the reading direction. Then an even sample of the book: up to 32 body pages for each side, spread over the whole book. Then every other page in order.
- Priority. The survey has the lowest priority. On a scanned page it runs the layout pass on the recognition worker, behind the shown page's layout pass, its recognition and search. The layout record that it makes is kept, so the word view opens that page at once later.
- Freeze. When the sample is done, the book profile freezes and does not change again. Pages that the survey analyzes later only get their own crops. So a page's crop never changes after the book profile exists.
- Storage. The profile and the page crops are kept in a new `DerivedBookFiles` directory of the download, beside the recognition cache and the admitted book. Removing the download removes them. The survey writes them atomically in batches. After ta-ukpf lands, it uses that shared atomic write. It resumes at the next open where it stopped.
- Pauses. The survey pauses while the book is closed and while the app is in the background.
- Cost. On a text layer page, one analysis takes one render at 1600 pixels and one hop. On a scanned page, it also takes one layout pass: 116 to 218 ms on the host. A book of 400 scanned pages costs a few minutes of worker time, once. The device acceptance measures it.

### The Original view

- The page shows its crop, fitted to the screen. It renders at the screen's width divided by the crop's share of the page width, within the existing render limits. So the text gets more of the screen's pixels.
- Pinch zoom and pan work on the cropped page as today, up to 6 times. A swipe on a zoomed page moves the page.
- A page never changes its crop while it shows. This avoids a jump during reading:
  - Until a page's crop is known, the page shows uncropped. A crop that becomes known later applies from the next page that the reader shows.
  - The next page in the reading direction gets its analysis first, so its crop is normally ready before the person turns.
  - A page that a jump or a scrub opens waits up to 300 ms for its crop before its first draw. After that it shows uncropped.
- In the first minute of a new book, before the profile freezes, pages show uncropped. From the next turn after the freeze, every page shows cropped.

### The switch

- "Trim margins" is a switch row in the glass Reading settings sheet, under the Pages row, for PDFs only. It is on by default.
- Off shows the full printed page in the Original view at once. On shows the crop at once. A change of the switch is the one time a shown page changes its crop.
- `ReaderSession` keeps the switch and saves it with the text size, so it lasts across runs. It is a preference, not a mode such as the page view.
- The word view always leaves out headers and folios, whatever the switch says. The text view still shows their words. Ticket tb-go0c leaves them out of the text view too.

## Tests

### Fixtures

All fixtures go in `test/reader/fixtures/reflow/`, with a README that records each source and its license.

| Fixture | What it holds | Source |
| --- | --- | --- |
| `scanned-page.pdf`, `scanned-page.layout` and `scanned-page.hocr` | One scanned page of a public-domain book, with italics, a footnote mark, a line-end hyphen, an indented paragraph and a figure with a caption. The layout record and the hOCR come from Bookfin's Tesseract on an Android emulator. | A page of the 1873 "The Raven" scan already in `tool/research/readers/evidence/text-quality/`, or another public-domain scan with those features |
| `footnote-page.pdf`, `footnote-page.layout` and `footnote-page.hocr` | One scanned page with raised footnote marks, six line-end hyphens in its prose, an indented paragraph, italics, a side note and footnotes in smaller type. Ticket t2-jfg1 added it, because the Raven page has no footnote mark, hyphen or indent. | Page 19 of volume 4 of Gibbon's "Decline and Fall" (1880), from the Internet Archive |
| `equation-page.pdf` | A born-digital page. It has a centered heading, two paragraphs, and an inline formula with a superscript. It also has a display equation, a small table, and a justified paragraph with wide word gaps and a line-end hyphen. Its display equation has raised marks and no stacked fraction. Both stacked fractions that ticket tb-xwlj tried made `_outOfOrder` reject the page's text layer, and the page then takes its text from recognition. | Made in the dev shell with Typst from `equation-page.typ` beside it |
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
- A turn past a page's last screen shows the next page's first screen. A turn back from a page's first screen shows the previous page's last screen. This holds in the word view and in the text view.
- No screen cuts a line, in either view, and no screen starts with a paragraph gap.
- A vertical drag on a reflowed page changes nothing.
- A text size step in the text view keeps the shown place on the shown screen.
- At the largest system text size, the Pages row shows Original, Page words and Text as whole words, and each segment can be tapped.
- The scrub deck shows original pages and starts no layout pass and no recognition.
- Running headers and folios are marked on every page that has them. A chapter title at a chapter's start, footnotes and figures stay content.
- A cover, a plate and a blank page do not change the side boxes. Every body page of a side gets the same crop. A page with a wide table gets a larger crop that holds all of it.
- Two body pages of one side show their text at the same size and place in the Original view.
- A page keeps its look while it shows, and a crop that arrives later applies at the next turn.
- Pinch zoom and pan work on a cropped page.
- Trim margins is on in a new install. Off shows the full page. The choice survives a restart.
- The word view shows no running header and no folio, and search still finds a header word.
- The survey resumes after a reopen, runs no page twice, and never delays the shown page.

Each module with state keeps one `checkInvariants`:

- `PageGeometry`, as above.
- The reflow pages of `PdfBook`: at most 16 pages, each with a geometry and an analysis that hold their invariants. An attached text that arrived has the digest of its reading text and a range of it for each reflow word.
- `PdfWordPages`: its images belong to the shown or the next screen, and their pixels are within the bound.
- The book crop: every page crop holds its content box, and every body page's crop equals its side's box.

### Device acceptance

On the Pixel 8 or an emulator through the T3 device tools:

- Open the three fixtures and one scanned book from the user's library. Take screenshots of the word view in cream and in night, at text sizes 14, 20 and 40, and of the text view.
- Measure the time from a turn to a new source page with cached text to its first screen. The target is 400 ms on the Pixel 8.
- Measure the time from a turn to a scanned page that was never recognized to its first word screen, and to its text. Compare them with the time to the first text screen before this epic.
- Measure the graphics memory of the reader with `dumpsys meminfo` while the person turns ten screens.
- Make sure that a turn inside a page drops no frame, with the frame timing overlay.
- Tune `_wordSizeRatio` once against an EPUB at size 20.
- Take screenshots of the Original view with Trim margins on and off, on a body page, a wide-table page and a cover.
- Measure the survey's time for each page on a text layer book and on a scanned book, and its total for one book.

## Decisions of 2026-11-10

The user settled both product decisions of this design on 2026-11-10. The doc above follows them.

| Decision | Choice | Where the doc applies it |
| --- | --- | --- |
| 1: the shape of the switch | Design A. The Pages row in Reading settings has three segments: Original, Page words and Text. At a large system text size, `PillChoice` hides its icons, and then stacks its segments in a column. | The switch to the text view |
| 2: how a page turns inside a source page | Design A. A reflowed source page is cut into screens of whole lines, and a swipe shows the next screen, as in the EPUB reader. The text view also changes to whole-line screens. A swipe past a source page's last screen goes to the next source page. | Screens and turns |

The designs that the user did not choose:

- Decision 1, design B: the Pages row keeps Original and Reflow, and a second row, "Reflow shows", appears while Reflow is on.
- Decision 2, design B: one scroll column for each source page, as the text view of today.

## Order of work

Ticket keys W0 to W10, with W0b and W6b, and T1 to T6 name the tickets. The table maps each key to its ticket id.

| Key | Ticket | Work | After |
| --- | --- | --- | --- |
| W0 | tb-t0ea | The layout pass on Android through Tesseract's C API, and one native handle | boo-pw1d |
| W0b | tb-bmmm | Measure the layout pass against full recognition on an emulator | W0 |
| W1 | tb-jidt | Scanned page geometry from the layout record, its disk cache, text attachment from hOCR, and the scanned and skewed fixtures | W0 |
| W2 | tb-xwlj | Word geometry from the text layer, and the equation fixture | W1 |
| W3 | tb-t8rh | Page analysis and `PdfBook.reflowPage` | W2 |
| W4 | tb-0mex | Column layout: wrap, baselines, paragraphs, hyphens, regions, captions, and `cutScreens` | W3 |
| W5 | tb-xjfi | Bands, `drawAtlas`, tints and the memory bound in `PdfWordPages` | W4 |
| W6 | tb-22fu | The word view in `PdfViewport`: waiting for words and for text, places, turns, failure | W5 |
| W6b | tb-zx7r | Cut the text view into whole-line screens with `cutScreens` | W6 |
| W7 | tb-9mcf | The page view choice in the session, the three-segment Pages row, and `PillChoice` at large text sizes | W6 |
| W8 | tb-mfkk | Selection, copy, search hits and screen reader nodes on word images | W6 |
| W9 | tb-fi98 | Drop caps | W6 |
| T1 | tb-z9h5 | Running headers, folios and content boxes in the page analysis | W3 |
| T2 | tb-lnak | The survey, the book profile and the crops, kept on disk | T1 |
| T3 | tb-valc | The cropped Original view | T2 |
| T4 | tb-nkz5 | The Trim margins switch | T3 |
| T5 | tb-m8xo | The word view leaves out headers and folios | T2, W4 |
| T6 | tb-go0c | The text view leaves out headers and folios (follow-up, not in the acceptance) | T2, W6b |
| W10 | tb-fb6j | Device acceptance and tuning | W0b, W6b, W7, W8, W9, T3, T4, T5 |

The cropping tickets need the page analysis (W3) and the geometry under it (W0 to W2). They do not need the word view's layout, bands or screens. So T1 to T4 can be built in parallel with W4 to W9, as soon as W3 lands. Only T5 waits for the column layout (W4), and T6 for the text view's screens (W6b).


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
