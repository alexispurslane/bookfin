# PDF reflow as the page's own word images

Date: 2026-11-09. Epic: boo-fval. Parent: boo-fs0n. Blocked by: boo-pw1d.

## Decision

On 2026-11-09 the user decided that every PDF reflows as word images. Bookfin cuts the printed page into its words and wraps those word images to the screen. The reader sees the real printed words, with their italics, accents, footnote marks and size ratios. The mistakes of text recognition stay hidden, because the reader sees the pixels and not the recognized letters.

- If the PDF's own text layer is usable, word geometry comes from it. Otherwise it comes from Tesseract's hOCR, which the recognition cache already keeps.
- A switch shows the page's recognized or extracted text in the reader's font instead of the word images. That is the reflow view of today.

This document decides these things:

- which parts of k2pdfopt Bookfin adopts
- the word geometry model and its two sources
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
| Word | A run of the reading text's `source` without white space, with its box on the page in page units. |
| Line | The words that the source prints on one line, in reading-text order, with the line's baseline. |
| Baseline | The line that the letters of a printed line sit on. A skewed scan has a sloped baseline. |
| Own baseline | The baseline under one word, from the bottoms of its letters that have no descender. |
| Block | A group of lines that the source prints as one column piece. hOCR names it `ocr_carea`. |
| Region | A part of the page that reflow keeps whole: a figure, a table, an equation or a drop cap. |
| Piece | One thing that reflow places on the screen: a word or a region. It has a source rectangle on the page, a target rectangle on the screen, and a range of the reading text. |
| Page analysis | The facts about a page that need its pixels: regions, the ink of words that recognition missed, the widths of line-end hyphens, and the body line height. |
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

### Our situation

- Bookfin runs on a phone such as the Pixel 8. It has a fast CPU, a GPU and a color screen with about 2.6 device pixels per logical pixel.
- Tesseract already runs on every page without a usable text layer. Its hOCR output has the page, block, paragraph, line and word boxes, each line's baseline slope and height, and Tesseract's own reading order. The recognition cache already keeps that output.
- A born-digital PDF has a text layer with exact boxes for each character.
- Places, search and the reflow view of today depend on the reading text. Its characters must keep their meaning.

### What we adopt and what we leave

| Part of k2pdfopt | Our choice | Reason |
| --- | --- | --- |
| Words from white gaps in the bitmap | Leave | hOCR and the text layer already give word boxes in reading order. |
| Column and row finding | Leave | Tesseract's layout analysis and the text layer's order give lines and blocks. |
| Wrap word bitmaps to the screen | Adopt | This is the feature. |
| Find ink that no word covers | Adopt, small | Only to find figures and the words that recognition missed (see "Page analysis"). |
| Straighten skew | Adopt per line | We align each word to its line's baseline and rotate it by the line's slope. We do not straighten the whole page first. |
| De-warp | Leave | Own baselines correct most of a curved line. Leptonica de-warp is a large native dependency. |
| Remove line-end hyphens | Adopt | See "Rejoined hyphens". |
| Keep the source's justification | Adopt | It keeps the formatting. |
| Keep figures whole and fit them to the width | Adopt | See "Regions". |
| One bitmap per reflowed page | Leave | A whole reflowed page at phone resolution costs too much memory at large text sizes. We draw word pieces from bands with the GPU. |
| Map reflowed boxes to native boxes for selection | Adopt the idea | Each piece keeps its reading-text range, so a selection maps to word images. |
| Its code | Leave | Its GPL and AGPL licenses cover any program that links it. We take only ideas. |

## Model

```mermaid
flowchart TB
  subgraph Producers["Word geometry producers (in a hop)"]
    TL["preparePdfPage<br/>text layer: characters and boxes"]
    HO["decodeRecognizedPage<br/>hOCR from the recognition cache"]
  end
  TL --> RT["PdfText<br/>reading text, digest,<br/>PageGeometry"]
  HO --> RT
  RT --> BK["PdfBook<br/>owns page texts and<br/>page analyses"]
  BK -->|render at 1600 px| AN["analyzePage (hop)<br/>regions, missed ink,<br/>hyphen widths, body line height"]
  AN --> RP["ReflowPage<br/>text, geometry, analysis"]
  RP --> LY["layoutColumn (hop)<br/>lines, paragraphs, pieces, screens"]
  SS["ReaderSession<br/>page view, text size"] --> LY
  LY --> WP["PdfWordPages<br/>column, band images,<br/>shown and next screen"]
  WP -->|renderPart| BK
  WP --> DR["WordScreen painter<br/>drawAtlas with tint"]
  VP["PdfViewport<br/>shown page and place"] --> WP
  VP -->|onAddress| SS
```

The reading text is the one authority over a page's text. Each producer that makes a reading text also makes its word geometry, in the same hop and from the same data. So the geometry always describes the text that places name. Everything after that is derived: the page analysis from the geometry and a render, the column from the analysis and the settings, and the band images from the column.

### Owners

| State | Owner | Changes when |
| --- | --- | --- |
| Reading text and its word geometry | `PdfBook`, with its cache of 16 page texts. `BundledEnglishText` keeps its 16 selected recognized pages, as today. | A page's text is read or recognized. |
| Page analysis of a page | `PdfBook`, in a new cache of 16 pages beside the page texts. | The word view first needs the page. |
| Body line height of the book in this session | `PdfBook`, beside the analyses. | A page with at least 8 prose lines is analyzed. |
| The page view: original, word view or text view | `ReaderSession`, in one enum that replaces the `reflow` bool. It lasts for the run of the app, as the reflow choice does today (t9-3n2m). | The person chooses a view. |
| Text size | `ReaderSession`, as today. | The person steps the size. |
| Theme | The app's appearance, as today. | The person chooses cream or night. |
| Column of the shown page, its screens, its band images | `PdfWordPages`, one per `PdfViewport`. | The shown page, the column width, the text size or the shown screen changes. |
| Shown page, shown screen and the shown place | `PdfViewport`, as today. | A turn, a jump or a new text. |
| Selection | The selectable of the shown screen. It is ephemeral UI state. | A long press, a handle drag or a new screen. |

## Word geometry

### The payload

`PdfText` gains one field, `geometry`. The digest still covers only `source`, so no saved place changes meaning. The geometry uses typed lists, so it crosses isolates as blocks.

```dart
/// Where the words of a page's reading text are printed. Lengths are in
/// page units: 1.0 is the page width, the origin is the top left corner,
/// and y grows down.
class PageGeometry {
  /// The page height in page units.
  final double height;

  /// For each word, in reading-text order: the first and the end
  /// character of the word in [PdfText.source].
  final Int32List ranges;

  /// For each word: left, top, right and bottom.
  final Float32List boxes;

  /// For each word: the y of its own baseline, or NaN when no letter of
  /// the word is known to sit on the baseline.
  final Float32List ownBaselines;

  /// For each line: the index of its first word. One more entry ends the
  /// last line.
  final Int32List lineStarts;

  /// For each line: the y of its baseline at x = 0, its slope, its height
  /// from ascender top to descender bottom, and its descender depth.
  final Float32List lineMetrics;

  /// For each block: the index of its first line, and one more entry.
  final Int32List blockStarts;

  /// The lines that start a paragraph in the source, when the source says
  /// so. Empty for a text layer.
  final Int32List paragraphStarts;
}
```

The invariants of `PageGeometry`:

- Word ranges are in increasing order and do not overlap.
- No word range holds white space.
- Every box has a positive area inside the page.
- Lines and blocks cover the words in order.

`PageGeometry.checkInvariants` makes sure of all of them, on demand.

### From hOCR

`decodeRecognizedPage` already reads every `ocr_line` and every `ocrx_word`. It builds the same `source` as today, character for character, so the same digest. It also records:

- each word's range in `source`, which it knows because it writes the words itself
- each word's `bbox`, divided by the width of the `ocr_page` box, which is the width of the raster that recognition read (1600 pixels today)
- each line's `baseline` (slope and offset from the line box's bottom left corner), `x_size` and `x_descenders`
- the `ocr_carea` that holds each line, as its block, and the first line of each `ocr_par`
- each word's own baseline. The descender set holds `g j p q y`, the comma, the semicolon and the like. If the word has no letter from that set, its own baseline is the bottom of its box. Otherwise it is that bottom minus the line's descender depth.

The recognition cache keeps the hOCR output as it is. So pages that Bookfin recognized before this epic get their geometry with no new recognition. `BundledEnglishText.version` does not change. A new version makes every saved place on a recognized page fail to resolve.

### From the text layer

`preparePdfPage` already receives each character's box in PDF points. It also receives the page width and height, and records:

- each word: a run of `source` without white space, as the reflowed text already splits it
- its box: the union of its characters' boxes, turned into page units with y flipped
- its own baseline: the median bottom of its characters outside the descender set
- lines: a word starts a new line in two cases. Its height overlaps the previous word's height by less than half the smaller height, or it starts to the left of the previous word. The text is a candidate, so its order is the reading order, and this rule follows it.
- blocks: a line starts a new block in two cases. The vertical gap above it is more than twice the median line pitch. Or its left edge moves by more than a quarter of the page width.
- each line's baseline: the median of its words' own baselines, with a slope of 0

### When the geometry is not usable

- A text layer can be a candidate while its boxes are not usable: a character without a finite box of positive area inside the page, or a word whose box spans more than three line heights. Then the page has no geometry. The word view shows that page in the text view, with no notice. Its places keep their meaning, because its reading text does not change.
- A text layer can have usable boxes while its order is not usable (`_textWarning` returns a reason). Then the page's reading text comes from recognition, as today, so its words come from hOCR. The text layer's boxes are not used. A second design sorts the text layer's words by position into a new reading text. We reject it. That text has a new digest, so every place that a person saved on such a page from the recognized text fails to resolve. Also, Tesseract's layout analysis finds columns better than a sort by position.
- A page whose reading text has no content shows the original page with the quiet line, as today.

## Page analysis

The word view needs facts that only the pixels know. `PdfBook.reflowPage(sourcePage)` gives the reading text, its geometry and its page analysis together. It renders the page at 1600 pixels wide, as recognition does, so hOCR boxes match the raster exactly. The analysis runs in a hop. It takes the raster and the geometry, and returns only small typed lists.

1. Ink. If a pixel's luminance is below half, the pixel is ink. The analysis works on a mask that is 4 times smaller in each direction. A 1600 by 2400 raster gives a 400 by 600 mask.
2. Word cover. It removes the ink inside each word box, grown by a fifth of the line height.
3. Components. It joins the remaining ink into 8-connected components. It drops specks smaller than a third of the body line height in both directions, as k2pdfopt's `-de` does.
4. Missed words. Some components lie inside a text line: they overlap the line's height by half, and they are no taller than 1.5 line heights. Each one becomes an unread word of that line. It has an empty range of the reading text, at the place between its neighbors. So every printed mark of a line shows, also the marks that recognition missed.
5. Regions. Components close to each other (less than half a body line height apart) join into one region. A word whose box lies more than half inside a region joins the region. Lines that fail the prose line test below join into one region with their neighbors that also fail it.
6. Hyphen widths. Some words end a line with a hyphen. For each one, the analysis looks inward from the word's right edge, within its last 0.6 line heights. It finds the white gap before the hyphen. On a text layer page, the hyphen's character box gives the width, and no pixels are needed.
7. Body line height. The median line height of the page's prose lines.

The prose line test has two parts. First, the line's words share a baseline within a third of the line height. Raised or lowered marks of at most two words are allowed. Second, no gap between its words is larger than 2.5 times the line's median word gap. Display equations and table rows fail the test. A line of fewer than 3 words is an exception. If its height is within 1.3 times the block's median line height, it passes. So short headings and last lines pass.

If more than 30 percent of a region's pixels are mid-tones (luminance between 0.2 and 0.8), the region is a picture. Otherwise it is ink, such as an equation, a table or a drop cap. The tint rules below treat the two kinds differently.

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
- When a word's own baseline is within a quarter of the line height of the line's baseline, the word aligns by its own baseline. This corrects a curved line near the spine. A word farther from the line's baseline keeps its offset, so a footnote mark stays raised by its source ratio.
- When a line's slope is more than 0.3 degrees, each of its words rotates by the opposite angle about its baseline point. The source rectangle grows by the rotation's extra width, so no ink is cut.
- The distance between reflowed baselines is the source's median baseline pitch, scaled. If a raised or lowered word needs more room, its line grows.

### Paragraphs

- A paragraph starts at the first line of the page, at each `ocr_par` start of hOCR, and where the geometry rule says so. The geometry rule applies to both sources. A line starts a paragraph in three cases:
  - The vertical gap above it is more than 1.5 times the block's median line pitch.
  - It is indented by more than half a body line height, and the line before it reached the block's right edge.
  - The line before it ended more than two body line heights short of the block's right edge.
- An indented first line keeps its indent, scaled, but at most three body line heights.
- Some paragraphs have all their lines centered on the block. Each line's left and right margins are both more than one body line height, and they differ by less than one. Such a paragraph stays centered. This covers headings.
- A paragraph whose source lines reach the block's right edge, except its last line, is justified. Its reflowed lines spread their gaps, except its last line. Other paragraphs are left aligned. This follows k2pdfopt's default of keeping the source's justification.
- The space between paragraphs is the source's extra gap, scaled, but at most two lines.

### Rejoined hyphens

A hyphen pair is two words. The first ends a source line with a hyphen. The second starts the next source line with a lowercase letter.

- When both halves land on one reflowed line, the first half's source rectangle loses the hyphen's width, and the second half follows with no gap. The two halves read as one printed word.
- When the halves land on different reflowed lines, the hyphen shows, as in print.
- The reading text does not change. A hyphen pair is a layout fact only. Search and copy of a split word are a separate bug (tb-a07f).

### Regions

- A region takes the place in the flow of the first word that it holds. A region without words goes before the first line, in reading-text order, that starts below the region's top and overlaps it in width. When there is no such line, it goes at the end of the column.
- A region keeps the page's scale. When it is wider than the column, it scales down to the column width. When it is taller than the screen, it scales down to the screen's height.
- A region stands alone on its lines and is centered.
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
| hOCR decode and text layer prepare, with geometry | A hop, as today |
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

The word images are only a picture of the reading text. Every text feature uses the reading text, as today.

- Search searches `PdfText.text`, as today. A hit opens the screen that holds the hit's first character.
- A place is the first character of the shown screen's first piece with a nonempty range, through `PdfBook.addressFor`. The representation stays `policy/engine/recognition-or-extracted/digest`. A place saved in the word view opens in the text view at the same character, and the reverse.
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

- Waiting. The word view waits for the reading text, as boo-pw1d leaves it. Then it waits for the page analysis, the column and the first screen's bands. During all of these, the original page shows under the thin progress line of today. One waiting flag in `PdfViewport` covers them. When the first screen is ready, it replaces the original page with no notice.
- Failure. If the analysis or a band render fails, the page shows in the text view. If the text fails, the quiet line of today shows over the original page.
- Turns. A swipe or a screen reader's scroll action turns as open decision 2 decides. The band images of the next screen render after the shown screen's bands. So a turn inside a page shows its screen in the next frame.
- Neighbor pages. The word view prepares no other source page. It starts no recognition for a page that is not shown.
- The scrub deck shows the original pages, as today. It starts no recognition and no analysis. A scrub lands on the first screen of its page.
- The scrub bar counts source pages, as today. t6-1luw (the bar's spoken value at the end of a page) stays a separate bug.

## Tests

### Fixtures

All fixtures go in `test/reader/fixtures/reflow/`, with a README that records each source and its license.

| Fixture | What it holds | Source |
| --- | --- | --- |
| `scanned-page.pdf` and `scanned-page.hocr` | One scanned page of a public-domain book, with italics, a footnote mark, a line-end hyphen and an indented paragraph. The hOCR comes from Bookfin's Tesseract on an Android emulator. | A page of the 1873 "The Raven" scan already in `tool/research/readers/evidence/text-quality/`, or another public-domain scan with those features |
| `equation-page.pdf` | A born-digital page with a centered heading, two paragraphs, an inline formula with a superscript, a display equation and a small table. | Made in the dev shell with Typst from a source file kept beside it |
| `skewed-page.pdf` and `skewed-page.hocr` | The scanned page turned by 2.5 degrees, with a light speck noise. The hOCR comes from the emulator. | Made in the dev shell from the scanned page |

### Behavior tests

Geometry:

- A recognized page gives the same reading text and digest as before this epic, so a place saved before it still resolves.
- Each word of a recognized page names the characters of its hOCR word.
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
- A word that recognition missed still shows, in its line.

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
- While recognition runs, the original page shows under the progress line. The first screen replaces it with no notice.
- A turn past a page's last screen shows the next page's first screen. A turn back from a page's first screen shows the previous page's last screen.
- The scrub deck shows original pages and starts no recognition.

Each module with state keeps one `checkInvariants`:

- `PageGeometry`, as above.
- The page analysis cache of `PdfBook`: at most 16 pages, each with the digest of its reading text.
- `PdfWordPages`: its images belong to the shown or the next screen, and their pixels are within the bound.

### Device acceptance

On the Pixel 8 or an emulator through the T3 device tools:

- Open the three fixtures and one scanned book from the user's library. Take screenshots of the word view in cream and in night, at text sizes 14, 20 and 40, and of the text view.
- Measure the time from a turn to a new source page with cached text to its first screen. The target is 400 ms on the Pixel 8.
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

Ticket keys W1 to W10 name the tickets. The table maps each key to its ticket id.

| Key | Ticket | Work | After |
| --- | --- | --- | --- |
| W1 | tb-jidt | Word geometry from hOCR, and the scanned and skewed fixtures | boo-pw1d |
| W2 | tb-xwlj | Word geometry from the text layer, and the equation fixture | W1 |
| W3 | tb-t8rh | Page analysis and `PdfBook.reflowPage` | W2 |
| W4 | tb-0mex | Column layout: wrap, baselines, paragraphs, hyphens, regions, screens | W3, decision 2 |
| W5 | tb-xjfi | Bands, `drawAtlas`, tints and the memory bound in `PdfWordPages` | W4 |
| W6 | tb-22fu | The word view in `PdfViewport`: waiting, places, turns, failure | W5 |
| W7 | tb-9mcf | The page view choice in the session and the settings switch | W6, decision 1 |
| W8 | tb-mfkk | Selection, copy, search hits and screen reader nodes on word images | W6 |
| W9 | tb-fi98 | Drop caps | W6 |
| W10 | tb-fb6j | Device acceptance and tuning | W7, W8, W9 |

If the user picks design A of decision 2, W6 also cuts the text view into whole-line screens.

## Sources

- [k2pdfopt home]: https://www.willus.com/k2pdfopt/
- [k2pdfopt options]: https://www.willus.com/k2pdfopt/help/options.shtml
- [bmpregion.c]: https://raw.githubusercontent.com/koreader/libk2pdfopt/master/k2pdfoptlib/bmpregion.c
- [textrows.c]: https://raw.githubusercontent.com/koreader/libk2pdfopt/master/k2pdfoptlib/textrows.c
- [wrapbmp.c]: https://raw.githubusercontent.com/koreader/libk2pdfopt/master/k2pdfoptlib/wrapbmp.c
- [koptinterface.lua]: https://raw.githubusercontent.com/koreader/koreader/master/frontend/document/koptinterface.lua
- Bookfin's recorded hOCR shape: `tool/evidence/reader/integrated/20261103/android/ocr-cache-readback.json`
- pdfium's character boxes through pdfrx 0.9.0: `FPDFText_GetCharBox` in `pdfrx_engine/lib/src/native/pdfrx_pdfium.dart`
