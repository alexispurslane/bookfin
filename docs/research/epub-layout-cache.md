# A disk cache of EPUB layout results

Ticket boo-ystu, 2026-11-09. The question was whether the native EPUB renderer can keep layout results on disk between opens and launches. It also asked which results are worth keeping, and what makes a kept result safe to use.

The answer is yes, for one result: the page map. The page map of a book is the list of true page starts of each section, for one value of the layout settings. A true page start is a page start that a section's main run reaches from the section start (see `PageStart` and `_SectionLayout.starts` in page_source.dart). The page map is tiny: about 3 bytes for each page. It reads back in a few milliseconds. Layout is deterministic enough that a kept start equals a fresh one. Prepared sections are not worth keeping. Table cell widths and the first place of each page are worth keeping after the page map.

## How the numbers were taken

- Host: `test/research/epub_layout_cache_test.dart`, with `BOOKFIN_LAYOUT_CACHE=1`, over the 93 books of `tool/reader/epub_corpus.json` (the corpus of `docs/research/native-epub-corpus.md`). It runs in `flutter test` on macOS with the bundled reader font, as the corpus test does. The host runs a debug (JIT) build on an Apple silicon Mac. The Mac's load was 8 to 22 on 10 cores, so the host times are noisy. Compare host times with each other, not with the device.
- Settings: 412 × 671 pixels with 20 pixel text (the corpus's `readerPage`), and 360 × 640 with 26 pixel text.
- Device: `tool/reader/layout_cache_probe.dart`, a profile build on a new arm64 Android 36 emulator (bookfin-ystu: Pixel 7 profile, 4 virtual CPUs, 2 GB). Three other emulators ran on the same Mac. The emulator was deleted after the runs.
- The survey ran three times, each in a new process. Each run compares its page starts with those of the run before it.

## What is worth keeping

| Result | Size on disk | Time to read | What it saves |
| --- | --- | --- | --- |
| The page map (true page starts of every section) | 379 KB for all 93 books at 412 × 671 @ 20 (124,643 pages, 3.0 bytes a page). Median 2.4 KB a book, largest 34 KB (Complete Shakespeare). 759 KB at 360 × 640 @ 26, largest 70 KB (Plato's Dialogues). | Decode: at most 0.64 ms a book on the host. Read and decode on the emulator: 1.2 to 15 ms. | The whole-book layout and prepare of t7-bbv1 at every later open. The wait for page numbers. The previous section's main run on a turn back into it. |
| The first place and the visible characters before each true page | Estimate: 5 to 7 more bytes a page (two variable-length integers for the place and one of at most 2 bytes for the count) | Same read | The line search of a jump or an open into a long paragraph or a table. The page-exact scrub bar (boo-ok9i) and time left (boo-02sx) before a section is prepared. |
| Table cell widths (the narrowest and widest content of each cell) | 16 bytes a cell. 39,726 cells in 52 of the 93 books, at most 21,820 in one book (Plato's Dialogues, 349 KB) | Same read | The measure of every row of a table before the first page in it: 2.5 s on the host for the middle of Roget's Thesaurus |
| Prepared sections (DOM, styled runs, hyphenation points) | Lower-bound estimate: 300 MB for the corpus for each settings value, 2.6 times the XHTML, 25 MB for Plato's Dialogues | At least the port copy of boo-rw7u (89 ms for Keats' 430,000-character section, whose prepare is 297 ms) | Prepare in a worker, which is 18 percent of the host's compute (40 s of 223 s) and runs off the UI isolate |
| Line breaks of each paragraph | Not measured | Not measured | Nothing that the page map does not save. A page must lay out its paragraphs again to draw them. |

### The page map

On the emulator, two launches of the probe gave these times in milliseconds. The prepare of every section ran in one worker call each, as the page source does. The layout of every section's main run ran on the UI isolate.

| Book | Sections | Pages | Prepare of all sections | Layout of all sections | Slowest section's layout | Page from a kept start, median / largest | Page map bytes | Write | Read and decode |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Gutenberg's Frankenstein | 32 | 607 | 479 / 726 | 532 / 878 | 58 | 0.3 / 15 | 1,854 | 14 / 14 | 1.6 / 6.1 |
| Standard Ebooks' Hamlet | 12 | 567 | 425 / 553 | 1,196 / 1,310 | 300 | 1.9 / 52 | 1,715 | 9 / 33 | 4.2 / 1.8 |
| Standard Ebooks' Poetry of John Keats | 6 | 1,083 | 933 / 872 | 1,797 / 2,259 | 1,782 | 1.2 / 14 | 3,257 | 14 / 12 | 1.2 / 7.3 |
| Gutenberg's Ulysses | 21 | 2,214 | 489 / 640 | 1,981 / 2,378 | 268 | 0.8 / 23 | 6,670 | 41 / 4 | 15.2 / 3.9 |
| Gutenberg's Roget's Thesaurus | 122 | 6,431 | 8,167 / 9,066 | 13,479 / 14,858 | 6,633 | 20.5 / 285 | 19,417 | 12 / 32 | 3.6 / 2.0 |
| Gutenberg's Jane Eyre | 57 | 1,507 | 849 / 1,164 | 1,501 / 1,514 | 136 | 0.3 / 22 | 4,579 | 4 / 25 | 1.2 / 3.7 |
| Gutenberg's War and Peace | 368 | 4,757 | 4,999 / 7,488 | 3,137 / 3,884 | 28 | 0.2 / 13 | 14,641 | 54 / 20 | 3.1 / 3.7 |
| Gutenberg's Complete Shakespeare | 278 | 11,393 | 6,641 / 10,569 | 8,303 / 10,976 | 145 | 0.4 / 17 | 34,461 | 6 / 59 | 1.5 / 10.0 |
| Gutenberg's Hong Lou Meng (Chinese) | 13 | 2,190 | 248 / 277 | 4,769 / 4,192 | 857 / 471 | 3.2 / 133 | 6,595 | 30 / 31 | 3.1 / 3.6 |

The "page from a kept start" column samples every tenth true page start. Each sample lays out one page alone, in a section that its main run laid out before. So its tables were measured already. The largest sample in Roget's Thesaurus, 285 ms, is a page in a section whose layout took 6.6 s.

The whole-book work of t7-bbv1 costs 1 to 25 s of compute for these books at every open: the prepare in workers and the layout on the UI isolate between frames. With a page map, an open does neither for any section that the reader does not visit.

On the host, the layout of a whole book took a median of 0.7 s and 5.0 s at the 90th percentile. The longest was 28.5 s (Plato's Dialogues). The host's layout took 183 s for the corpus, and its prepare 40 s.

### What a page map saves, case by case

| Case | Today | With a page map |
| --- | --- | --- |
| Open at a saved place | The anchored page at once. The page number waits for the main run to pass the page: on the host, up to 4.5 s in Roget's Thesaurus and 1.9 s in Standard Ebooks' Divine Comedy for the middle of the largest section. | The true page and its number at once. The line search stays. The time to the first page does not change, because the page map reads in parallel with the admitted book (t7-rcyp). |
| Whole-book page numbers, the scrub bar and time left (boo-jglf, boo-ok9i, boo-02sx) | Known after the whole-book work of t7-bbv1 ends: 1 to 25 s on the emulator for the books above | Known at open |
| A turn back from a section's first page into the previous section | If the background work did not finish the previous section, the turn waits for its whole main run: 1,782 ms on the emulator for Keats' section 2 | One page from the section's last kept start, after the section's prepare |
| A jump (scrub or contents) | The anchored page after the line search. The true page and its number after the main run passes the place. | The true page and its number after the line search and one page |
| A turn into the next section | Prepare and the first page | The same. The page map holds no prepared section. |

### The first place of each page

The line search (`LineSearch` in layout.dart) finds the page start of the line that holds a place. It is fast for most places: a median of 0.6 ms on the host for the middle of each book's largest section. Two kinds of item make it slow:

- A long paragraph. The search counts the lines of its segments before the place. Standard Ebooks' Ulysses took 164 ms, Bleak House 63 ms.
- A table. The search measures every row of the table for its column widths first. Roget's Thesaurus took 2,502 ms for the middle of its largest section, which is one table of 1,187 cells.

A page map that also keeps each true page's first place (`LaidPage.startPlace`) finds the true page of a place by a binary search. The page source then lays out that one page and makes sure that it holds the place. If the place is after the page's last shown place, the page after it holds the place.

t5-q0hs built this lookup (`firstPageFor` and `LaidPage.lineOf` in layout.dart). The corpus run checks it against `lineStart` and the true page start before the line (see "Results of t5-q0hs" below). But the lookup does not remove the slow part of a jump into a long paragraph or a table. A page cut from a kept start inside a long paragraph counts the lines of the paragraph's earlier segments. A page cut inside a table measures the whole table. The line search does the same work, and both keep the result in one cache on the item. So the page from the kept start costs what the line search cost, and a page after a line search costs almost nothing. t5-s1vy (table cell widths) and t5-lfsm (the line counts of long paragraphs) keep those results in the map.

### Results of t5-q0hs

The corpus run (`BOOKFIN_EPUB_CORPUS=1`, 2026-11-09) checks the lookup at five places on every page: the page's first and last place, the place after its last, and the start and the middle of its middle line. It compares the lookup's page with the true page that holds the line that `lineStart` gives.

| Settings | Pages | Places checked | Lookup misses | `lineStart` disagreements | Map bytes, format 2 | Map bytes, format 3 |
| --- | --- | --- | --- | --- | --- | --- |
| 412 × 671 @ 20 | 124,643 | 620,791 | 0 | 0 | 393,168 (3.2 a page) | 955,814 (7.7 a page) |
| 360 × 640 @ 26 | 251,302 | 1,253,453 | 0 | 2 | 773,463 (3.1 a page) | 1,895,638 (7.5 a page) |

The median map of a book grows from 2.5 KB to 6.0 KB at 412 × 671 @ 20. The largest map grows from 70.5 KB to 176 KB (Plato's Dialogues at 360 × 640 @ 26). A map of 175 KB reads in 2 ms and writes in 4 ms on the host, file access included.

The two disagreements are in Gutenberg's Leaves of Grass (Kindle file), section 188. Page 44 ends with a line of only white space, and the line search picks it for a place on the first line of page 45. The lookup finds page 45, which shows the place, as `ChapterLayout.pageAt` does. t5-odvj fixes the line search.

Two kinds of page made the first form of the lookup miss, and the lookup now handles both:

- A table row taller than a page. Its fragments interleave over pages: a later cell of the row shows on the row's first page, while its first cell goes on over the next pages, whose first places are earlier. The lookup looks at all pages of a split row together (Standard Ebooks' Wealth of Nations, section 44).
- A place after everything that the rest of a section shows, before a last page that shows nothing. Its line is the last line that shows something (Gutenberg's Divine Comedy, section 2).

A jump to the true page at the middle of the largest section, after the section's prepare, on the host with a load of 5 to 7 (`test/reader/epub/page_map_jump_test.dart`), in milliseconds:

| Book | No map, true page | No map, page at the line | With a map, true page |
| --- | --- | --- | --- |
| Gutenberg's Roget's Thesaurus (section 1) | 1,724 / 1,748 | 978 / 948 | 919 / 1,006 |
| Standard Ebooks' Ulysses (section 18) | 316 / 349 | 134 / 150 | 135 / 149 |
| Standard Ebooks' Bleak House (section 57) | 32 / 33 | 5 / 4 | 4 / 4 |

With a map, a jump does no line search and gives the true page at the cost of the page at the line. A format 2 map gave the true page at that cost too, through the line search, so this ticket makes no jump faster. The page from a kept start inside a table or a long paragraph does the work that the line search did: it measures the table, or it counts the lines of the paragraph's earlier segments. t5-s1vy and t5-lfsm keep those results in the map.

### Table cell widths

A run that starts in a table needs the narrowest and widest content width of every cell of the table (`LayoutRun._measured`). A line search in a table needs them too. That cache lives in an `Expando` on the table item. When the page source evicts the prepared section, the cache goes with it. Kept on disk, the widths remove the measure of the whole table from a jump or an open into it. A run from a kept start inside an unmeasured table also measures the whole table (the note on the `LayoutRun` constructor).

### Prepared sections

Prepared sections are not worth keeping:

- Size: at least 2.6 times the XHTML for each settings value, against 3 bytes a page for the page map. A prepared section depends on the page width, height, text size and theme, because prepare turns lengths into pixels and colors.
- Time: decoding a prepared section must build the same object graph that the worker builds now. The port copy of boo-rw7u is a floor for that: 89 ms of Keats' 297 ms prepare. Prepare already runs in a worker, off the UI isolate.
- Upkeep: a binary codec for the DOM, the flow items and the styles must change with every change to prepare. Each missed change is a stale result.
- Other work covers the cases where prepare matters. t7-49gt covers a page of a very large section. t7-rcyp removes the second parse and the image decodes of admission. With a page map, a section that the reader does not visit is never prepared.

## What a kept result depends on

The page map holds the output of prepare and layout. The table lists each input to them, where it comes from, and how the key covers it.

| Input | Where it comes from | In the key as |
| --- | --- | --- |
| The book's sections, style sheets, image sizes, language and embedded fonts | The admitted publication | The book identity: `Publication.identity`, or the identity that the admitted record of t7-rcyp keeps |
| Page width and height in logical pixels | The viewport's size (`EpubViewport`) | The exact 64-bit values |
| Text size, after the system text scale | `MediaQuery.textScalerOf(context).scale(reader.fontSize)` in screen.dart | The exact 64-bit value |
| Theme (night or cream) | `PageSettings.night` | Not in the key. In all 4,573 sections of the corpus, the night colors cut the same page starts. |
| Device pixel ratio | Not an input. `ui.Paragraph.layout` takes logical pixels. The ratio applies only to the drawn picture. | Not in the key |
| Prepare, layout, the reader's CSS, the hyphenation patterns, the bundled fonts (Source Serif 4, Noto Sans Math Arrows), Flutter's engine (Skia, SkParagraph, HarfBuzz, ICU, FreeType) | The app package | The app package's install time (see below) |
| System fallback fonts, for characters that no bundled or embedded font has | The operating system | The operating system's build fingerprint |
| The locale | The platform | The platform's locale list |

The app's version (`version: 0.1.0+1` in pubspec.yaml) is the same in every build, so it cannot stand for the code. Two values change with every install of a new APK, on Android: `PackageInfo.lastUpdateTime`, and the path of the installed APK. `lastUpdateTime` is simpler. The existing `bookfin/device` channel in MainActivity.kt can return it with `Build.FINGERPRINT`. On macOS the same channel can return the modification time of the app bundle's executable and the system version. A debug build changes its code by hot reload with no install. So a debug build reads no page map, except in a test that asks for it.

The proposed key:

```
format version
book identity
width, height, text size (exact 64-bit floats)
app install time (Android lastUpdateTime, macOS executable modification time)
operating system build (Android Build.FINGERPRINT, macOS version)
platform locales
```

The file name is a hash of the whole key. The file's header repeats the whole key. If the header does not equal the key in full, the reader ignores the file.

## Determinism

For the page map to be safe, a fresh layout must give exactly the kept starts. The survey tested this four ways:

1. Across processes on the host: three runs of the survey gave the same page starts in all 93 books at both settings. Each run was a new process. The corpus has 124,643 pages at 412 × 671 @ 20.
2. A page from a kept start: the survey prepared each section again, as a new object with no table measured. A run from each of the 124,643 true page starts cut one page. Each page's layout key (`pageKey` in test helpers) equals the main run's page, and its following start is the next kept start. No page differed.
3. Across launches on the device: two launches of the probe gave the same starts in all ten books, including the Chinese book. A third launch of the Chinese book with the app's locale set to `ja-JP` gave the same starts too.
4. Across platforms: the emulator and the macOS host gave the same starts for Frankenstein, Hamlet, Keats and Die Verwandlung. They differed for Ulysses, Roget's Thesaurus, Jane Eyre, War and Peace, Complete Shakespeare and Hong Lou Meng. In Jane Eyre, one section of 57 differs: on one page, Android needs one more line than macOS. The paragraphs on that page use only ASCII letters, curly quotes and the em dash, which the bundled Source Serif 4 has. So no fallback font causes it: the two platforms' text stacks wrap a few lines differently with the same font. A page map must never move between platforms.

Point 4 shows that a change of the text engine changes page starts. The app install time covers a Flutter upgrade, a changed font and changed layout code. Bookfin sets `android:allowBackup="false"`, so Android never restores a page map on another device.

The survey did not test a Flutter upgrade, an Android system update, or an update of the system's fallback fonts. The key covers the first two. For the third, Android 12 and later can update some system fonts (for example the emoji font) without a new build fingerprint. This ticket did not test that on a device. The check on use below catches that drift on every page that the reader sees.

## A kept start in place of a laid page

A kept start stands in for a laid page exactly. A page cut reads only the strip from its start down to one page height (the header of layout.dart). Test 2 above shows it for the whole corpus. So the page source can show the page at a kept start by laying out only that page's strip, as its anchored run does today.

With a page map, a section's `starts` and `mainDone` are known before any run. In the page source today:

- `pageAt(place, anchored: true)` finds the line's start. Then `knows(line)` holds, so the request gets the true page at `trueStart(line)`, and not the page that starts at the line.
- `_runAt` finds no main run and `mainDone` true, so it starts a run from the kept start in the anchored run's slot. A forward turn goes on in the same run. A turn back starts a new run from the previous kept start.
- `numberOf` gives the number and the count at once, and `mainRun` requests complete at once.
- The whole-book work of t7-bbv1 skips every section whose page map is kept. It does not even prepare those sections.

The anchored run becomes the general run from a known start. The rule in `_take` drops the anchored run "once the main run passed its start". With a page map, it drops the run as soon as no pinned page or request needs it. A builder can keep that rule, or rename the run to say what it now is.

### The check on use

Every page that a run lays out from a kept start checks the page map. A page that starts at kept start S has a following start N, which the run finds fresh. The page map is stale in two cases:

- N is not the next kept start.
- The run's page is the section's last page and the map has more starts, or the reverse.

Then the page source drops the page map for this settings value and deletes its file. It lays out main runs again, as it does today without a map.

At open, the pager also makes sure that the true page holds the saved place: the line's start must come before N. Else the page map is stale, and the pager shows the anchored page at the line instead.

The check costs nothing: the run finds N anyway. A drift that the check catches shows no page that skips or repeats text. A drift on a page that the reader never sees can make a page number wrong by one. Today, a page number before a main run ends has the same limit.

## Saved reading places

A page map never changes which place a saved address opens. The pager resolves an address to a place from the DOM alone: the CFI and the quote (`_resolve` in pager.dart). The page map only changes which page shows that place: the true page that holds it, and not the page that starts at its line. The pager reports the saved address unchanged at open. Its invariant (the shown page holds the shown place) still holds, because of the check on use.

After the reader turns a page, the saved address is the new page's first place. With a page map, that page is a true page. Without one, it can be a page of the anchored run's chain until the main run catches up. Both are places that the reader reached, so no reading place is lost. This is the same difference that exists today between a section whose main run ended and one whose main run did not.

A page map holds no reading place. Losing it, or setting it aside, loses only layout work.

## Format and storage

- Owner: a page map store, one per open book, owns the file. The page source stays the one owner of the starts in memory. It takes the kept starts at open, and gives the store each section whose main run ends.
- Where: a directory `.bookfin-layout` beside the download's file, as `.bookfin-mobi` and `.bookfin-ocr` are. `DerivedBookFiles.bytes` counts it and `DerivedBookFiles.remove` removes it, so removing a download removes its page maps.
- Encoding: binary. A header has a magic number, the format version and the whole key. Then comes the section count. Each section has a flag for a complete main run, the start count, and its starts. Each start is three unsigned variable-length integers: the item's step from the previous start, the line (its step from the previous line in the same item), and the part. Later tickets add the first places and the table widths as separate blocks. A CRC-32 of the whole file comes last. JSON was 3.4 times larger (1.27 MB for the corpus) with no gain.
- Which isolate: the UI isolate encodes and decodes it. The largest book decodes in 0.2 ms on the host. One hop to a worker has a fixed cost of 1 to 2 ms (boo-rw7u). The code says why in a comment, as engine rule 1 asks.
- Reads: at open, in parallel with the admitted book. The page source never waits for the page map. A map that arrives after the first request still seeds the sections that no run started.
- Writes: the store writes after a section's main run ends, at most once every few seconds. A close of the book and a move of the app to the background also start a write. Each write goes to a temporary file, then a rename, so a kill leaves the old or the new file.
- Limits: at most four settings values for each book, the most recently used by file time. On the first open after an app update, the store deletes the book's files whose key names another install. The largest file in the corpus is 70 KB, and the files go with the download.
- A file that cannot be read: a header that names another key is not this book's map, so the store ignores it. A file with a bad CRC, a short file or a decode error is broken. The store renames it to `.bad`, one per book, replaced each time. The page source then lays out as it does with no map. Nothing is reported, and reading never waits for it.

## Two designs

The open decision is how far to trust a kept page map.

| Design | Trust | Background work at each open | Drift on a page the reader never sees |
| --- | --- | --- | --- |
| A: checked on use (recommended) | The page map is the true page starts until a page that the reader sees contradicts it | None for sections with a page map | Stays until the reader reaches it, or until the key changes |
| B: kept, then filled in again | The page map is shown first, as engine rule 2 asks for cached data. The whole-book work of t7-bbv1 still runs, and its results replace the page map in place. | The whole-book prepare and layout, as without a map: 1 to 25 s of compute on the emulator for the books above | Fixed in the same session |

Usage at open, in both designs:

```
A: read map -> seed page source -> show true page -> no whole-book work
B: read map -> seed page source -> show true page -> whole-book work -> compare -> replace
```

What both share: the key, the file and its place, the check on use, the true page at open, and page numbers at open.

Design A is recommended. Drift never showed in three host runs over the corpus or in two device launches. The key covers every input that the survey found, and the check on use catches drift on every page that the reader sees. Design B pays the whole-book compute and battery at every open to fix drift that no test showed.

## Follow-up tickets

The work goes in this order (parent boo-b2ey):

1. t5-9tbu: report the app's install and the system's build to Dart for cache keys (the `bookfin/device` channel on Android and macOS).
2. t5-4lbx: keep a book's page map on disk: the store, its format, its file and its limits. It does not need the page source.
3. t5-4l4d: open a book with its kept page map: seed the page source, check on use, and save as sections end. It needs 1, 2 and t7-bbv1, whose order of work it changes.
4. t5-q0hs: keep the first place and the visible characters of each true page in the page map. Then a jump or an open finds its true page without the line search. It needs 3.
5. t5-s1vy: keep table cell widths in the page map. It needs 3.

boo-jglf, boo-ok9i and boo-02sx get their numbers at open once ticket 3 is done, but they do not depend on it.

## How to measure again

1. Fetch the corpus with `python3 -I tool/reader/fetch_epub_corpus.py` in the dev shell.
2. Run the host survey:

   ```
   nix develop --command bash -c 'BOOKFIN_LAYOUT_CACHE=1 flutter test test/research/epub_layout_cache_test.dart'
   ```

   Each run writes `.cache/layout-cache-survey/run-<n>.json` and compares its page starts with the run before it. `BOOKFIN_LAYOUT_CACHE_BOOKS` takes book ids, separated by commas.
3. Serve the books and a plan as the comment at the top of `tool/reader/layout_cache_probe.dart` describes. Use a device that no one else uses.
4. Build and install the probe's profile build on that device.
5. Read the results with `adb -s <device> logcat -d | grep LAYOUT_CACHE_PROBE`. The `startsSha256` of a book equals the SHA-256 of the survey's `starts` for that book and settings, in compact JSON.
