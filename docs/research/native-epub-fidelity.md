# The native EPUB renderer against epub.js: fidelity check and saved places

Date: 2026-11-08. Ticket: tc-pshi (E18). Epic: boo-b2ey. Design: `docs/plans/native-epub-reader.md`, "Places that epub.js saved" and "Fidelity check against epub.js".

This check measured the product renderer (`lib/reader/epub`) against epub.js one last time, before tc-rap6 removes epub.js. It also kept what epub.js measured and saved as test fixtures, so that the tests outlive epub.js.

## Result

Body text breaks lines and pages where epub.js breaks them, above both targets. Every page start that epub.js saved opens on a native page whose first line holds it. Where a native page starts on the same character as an epub.js page, the native reader saves the same JSON as epub.js. Two contents entries of one book open on the page before their target. Ticket t9-ousp records that bug.

| Check | 20 pixels | 23 pixels | Target |
| --- | --- | --- | --- |
| Body text line starts (12 sections) | 26,447 of 26,451 (99.98 %) | 31,745 of 31,757 (99.96 %) | 99.9 % at 20 pixels |
| Body text page starts | 1,460 of 1,482 (98.5 %) | 2,024 of 2,048 (98.8 %) | 98 % at 20 pixels |
| Body text sections with the same page count | 11 of 12 | 11 of 12 | None |
| Page starts that epub.js saved, opened on a page whose first line holds them (all ten books) | 663 of 663 | 708 of 708 | All |
| Native pages that start where an epub.js page started, with the same saved JSON | 412 of 412 | 467 of 467 | All |
| Contents entries: same saved JSON as epub.js | 729 of 729 | Not size dependent | All |
| Contents entries: open on a page that shows them | 727 of 729 | Not measured | All |
| Search hits: same saved JSON, open on a page whose first line holds them | 479 of 479 | Not size dependent | All |

The trial (`docs/research/native-epub.md`) had 661 of 661 and 706 of 706 saved page starts. This check covers more pages, because it records every page of the fixture books.

The body text group has 12 sections of the 7 downloaded books. The trial's body text group also held the fixture books. Here their pages are in the places fixture. All 10 page starts at 20 pixels and all 12 at 23 pixels agree there.

## The other groups

The trial's grouping stays. Only body text has a target.

| Group | Sections | Line starts at 20 pixels | Page starts at 20 pixels | Page starts at 23 pixels | Cause |
| --- | --- | --- | --- | --- | --- |
| Standard Ebooks imprint | 5 | 173 of 173 | 10 of 10 | 15 of 15 | Text agrees. epub.js counts 75 pages, of which 73 are empty columns. |
| A Christmas Carol | 2 | 4,864 of 4,934 | 117 of 267 | 104 of 351 | The contents are tables, and the Gutenberg license sets `all: initial`, so Chromium draws it in Times. |

In body text, Keats' 1,073-page poetry section holds 22 of the 22 differing page starts at 20 pixels. As in the trial, Flutter rounds each line height to a whole pixel and Chromium does not. Ticket tc-n6wv (fractional line positions) uses `fidelity_test.dart` to measure its change.

## The defect that the check found

A contents entry opens, as reader.js `resolveDestination` finds it, the first text node of its element at offset 0. In Standard Ebooks and Gutenberg books that node often holds only white space. `lineStart` and `ChapterLayout.pageAt` compare places in DOM order, so they put such a place on the line before its next visible character. Two cases follow:

- In Keats, the entries "Sleep and Poetry" and "Mrs. Cameron and Ben Nevis" open on a page that shows only the last line of the poem before. The person does not see the poem that they chose.
- In A Christmas Carol, the entry "IN PROSE" opens on a page that starts one line before the heading. The page shows the heading.

No saved place moves: epub.js page starts and search hits never pointed into such a node. Ticket t9-ousp records the fix. Until it merges, the on-demand run of `saved_places_test.dart` fails on the se-poetry contents test.

## The fixtures

The files are in `test/reader/epub/fixtures/`. They hold numbers and short strings only: visible character indices, CFIs, 120-character quotes, progress values, contents titles and hrefs, and search excerpts. No book file is committed.

| File | Books | Key | Size | Contents |
| --- | --- | --- | --- | --- |
| `epubjs-places.json` | The 3 fixture books of `tool/showcase_media.dart` | Book name, with its publication identity | 9 KB | Per section and size, each page's start (visible index of its first line), CFI, quote and progress. Per book, each contents entry's place and the hits of three phrases. |
| `epubjs-corpus-places.json` | The 7 downloaded books | SHA-256 of the book file | 628 KB | The same records for the compared sections. Up to 40 pages per section, as in the trial. |
| `chromium-layout.json` | The 7 downloaded books | SHA-256 of the book file, then section index, then size | 484 KB | The line starts of each page of each compared section, as visible character indices. |

A visible character index counts the characters of the section's body that are not white space, as reader.js `progressAt` counts them.

There are three search phrases. "morning" is a word that also starts sentences. "the door" is two words that a line can break between. "lantern" is a rare word. Ticket tc-866u can hold native search against these hits.

The fixture books are zipped again with a fixed file time (`showcaseBooks` in `test/reader/epub/trial/book.dart`), because the publication identity also hashes the archive bytes.

## The tests

| Test | When it runs | What it checks |
| --- | --- | --- |
| `test/reader/epub/saved_places_test.dart`, fixture books | Always | The fixture belongs to the same book. Each saved page start resolves (`placeOf`), its quote matches, and the anchored page (`PageSource.pageAt(anchored: true)`) has a first line that holds it. Each native page that starts on an epub.js page start saves the same JSON (`pageLocation`). Each contents entry (`destination`) and each search hit (`placeOf`) saves the same JSON (`hitLocation`). Each opens on a page that shows it. |
| `saved_places_test.dart`, downloaded books | On demand (`BOOKFIN_EPUB_TRIAL=1`), for each file with the recorded SHA-256 | The same checks |
| `test/reader/epub/fidelity_test.dart` | On demand (`BOOKFIN_EPUB_TRIAL=1`) | Native line starts and page starts against `chromium-layout.json`, by group, at both sizes. It asks body text at 20 pixels for 99.9 % of line starts and 98 % of page starts. It writes `.cache/epub-trial/results/fidelity-native.json`. |

The design asks contents entries and search hits to open "on the page that shows their target". The ticket asked that each recorded place open on a page whose first line holds it. The tests follow the design for contents entries and search hits, and the ticket for saved page starts. All search hits also pass the stricter check.

Three temporary faults made the tests fail for the right reason. A changed quote in `epubjs-places.json` failed the quote check and the JSON check. A `wordStart` that returns the page start unchanged failed the JSON check with CFI offsets one character off. A page 11 pixels shorter dropped body page starts to 56 % in the fidelity test.

## How to run it again

Chromium 138.0.7180.0 (`/Applications/Chromium.app`, which reports `Chrome/138.0.7180.0`) made these fixtures. It ran headless at 412 × 671 pixels with Source Serif 4. The recorder needs Chromium at that path or at `CHROME_BIN`, and the epub.js assets that tc-rap6 removes. Run each command in the dev shell (`nix develop --command bash -c '...'`) from the repository root.

1. Put the downloaded books in `.cache/epub-trial/books/`, which git ignores. `docs/research/native-epub.md`, "Reproduce", gives their sources. `test/reader/epub/admission_test.dart` lists their SHA-256.
2. Write the plans at both sizes:
   `BOOKFIN_EPUB_TRIAL_PLAN=1 flutter test test/reader/epub/trial/fidelity_test.dart` and
   `BOOKFIN_EPUB_TRIAL_PLAN=1 BOOKFIN_EPUB_TRIAL_FONT_SIZE=23 flutter test test/reader/epub/trial/fidelity_test.dart`.
3. Record with epub.js, once for each size (`20` and `23`):
   `node packages/flutter_epub_viewer/engine/trial/compare.cjs .cache/epub-trial/fidelity-20/plan.json .cache/epub-trial/admitted .cache/epub-trial/fidelity-20/chromium`.
4. Write the fixtures: `BOOKFIN_EPUB_TRIAL_FIXTURES=1 flutter test test/reader/epub/trial/fidelity_test.dart`.
5. Run the checks: `BOOKFIN_EPUB_TRIAL=1 flutter test test/reader/epub/saved_places_test.dart test/reader/epub/fidelity_test.dart`.

After tc-rap6, only step 5 can run. It needs the downloaded books and no Chromium.
