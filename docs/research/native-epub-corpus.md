# Native EPUB renderer: corpus run

The corpus run checks the native EPUB renderer (`lib/reader/epub/`) on 93 public-domain books. It looks for exceptions, broken saved places, approximated features and slow paragraphs. It runs on demand and is not part of the normal test run. The design is "Testing / Corpus test" in `docs/plans/native-epub-reader.md` (E19, ticket tc-4f3q).

## Commands

All commands run in the dev shell from the repository root, for example `nix develop --command bash -c '...'`.

1. Download the books: `python3 -I tool/reader/fetch_epub_corpus.py`. The script downloads into `.cache/epub-corpus/books/`, which git ignores. It asks for one file at a time and pauses 3 seconds after each request. It makes sure that each file has the size and SHA-256 that the list pins. It skips the books that are already present and correct.
2. Run the checks: `BOOKFIN_EPUB_CORPUS=1 flutter test test/reader/epub/corpus_test.dart`. Each book is one test. After each book, the run writes `.cache/epub-corpus/results.json`.
3. To check one book, add `--plain-name <id>`, for example `--plain-name pg-24264-hong-lou-meng`. To check several books, add `--name '^(id-one|id-two)$'`.

The Kindle files need the MOBI converter. The dev shell sets `BOOKFIN_MOBI_LIBRARY` for it.

To add a book, add an entry with `"sha256": null` and `"bytes": null` to `tool/reader/epub_corpus.json`. Then run the fetch script with `--pin`, which records the size and SHA-256 of each book that the list does not pin yet. If a source rebuilds a book, the fetch script refuses the new file. Standard Ebooks rebuilds its books from time to time. To pin the new file, set its `sha256` and `bytes` to null, delete the old file and run `--pin` again.

## The corpus

`tool/reader/epub_corpus.json` gives each book's id, title, source, URL, SHA-256, size, format and the reason that it is in. The books take 232 MiB.

| Source | Format | Trial books | New books | Kinds |
| --- | --- | --- | --- | --- |
| Standard Ebooks | EPUB | 5 | 36 | Novels, plays (dialogue set as tables), poetry, Plato's dialogues, a dictionary, translations with endnotes |
| Project Gutenberg | EPUB 3 with images | 2 | 39 | Poetry, plays, tables of numbers, illustrated children's books, two reference books (Roget's Thesaurus, The Devil's Dictionary), a German text and a Chinese text |
| Project Gutenberg | Kindle (KF8), converted by libmobi | 0 | 8 | An illustrated children's book, illustrated novels, a play, poetry, tables, a long novel |
| Bookfin's test fixture | EPUB | 3 | 0 | The small books that `tool/showcase_media.dart` makes. The test makes them, and nothing downloads them. |

The ten trial books are the books of `docs/research/native-epub.md`. The seven downloaded ones are the files that the trial and the fidelity fixtures used.

## What the run checks

The run admits each book with `Publication.admit`, as Bookfin does. It converts a Kindle file first, with `importMobi`. It reads each section as the page source does: with the book's own style sheets (`Publication.bookStyles`), the admitted image sizes and the book's embedded fonts. It checks every section at two page settings: 412 x 671 pixels with 20-pixel text, and 360 x 640 pixels with 26-pixel text.

| Check | What counts as a failure |
| --- | --- |
| Admission, conversion, support report, prepare, fonts, layout, places, runs from page starts, drawing | Any exception. The run notes the check, the section and the page settings, and goes on with the next section. |
| The main run, one flow item per step | The stepped run and a run in one step cut different pages, or `LayoutRun.checkInvariants` fails. |
| The CFI round trip of every page start | The CFI that Bookfin saves for a page start opens another page. The run also counts the page starts whose CFI and quote come back unchanged. |
| A run from a page start | It cuts other pages than the main run, over the 5 pages that it cuts first. A section with more than 100 page starts uses 100 evenly spaced ones, which include its last page (see "Limits"). |
| Drawing | The first, middle and last page of each section draw with their images at 2.625 image pixels per layout pixel. |
| Support report | It lists the features that the renderer approximates, and the features that it does not support, by section. It is not a failure. |
| Slow items | It lists each paragraph or table whose layout step takes more than 8 ms, and the layout time per 10,000 visible characters. It is not a failure. |

## Results of 2026-11-08

The results come from a host run under `flutter test`, with JIT code and CPU raster. Other agents loaded the machine to 4 to 40 on 10 cores. Times are therefore high and noisy. Compare them only with each other.

The run checked all 93 books, in three parts. The first part ran the books in list order and stopped at its two-hour limit during Roget's Thesaurus. The second part ran the 22 books after Roget's, and the third part ran Roget's alone.

| | 412 x 671 at 20 px | 360 x 640 at 26 px |
| --- | --- | --- |
| Pages | 116,904 | 233,698 |
| Page starts whose CFI opens their own page | 116,900 of 116,900 | 233,641 of 233,694 |
| Page starts whose CFI and quote come back unchanged | all | all |
| Runs from a page start | 89,574 | 154,406 |
| Runs that cut other pages | 19 (one book) | 0 |
| Sections whose runs were limited to 100 page starts | 169 | 494 |
| Paragraphs and tables over 8 ms | 420 (in 40 books) | 636 (in 39 books) |
| Layout time per 10,000 visible characters, median of the books | 9.8 ms | 11.9 ms |
| Layout time per 10,000 visible characters, highest | 74 ms (Hong Lou Meng) | 129 ms (Leaves of Grass) |

ROGET_ROW

### Findings

| Category | Count | Books | Ticket |
| --- | --- | --- | --- |
| Exceptions | 0 | | |
| Broken saved places | 53 page starts at 26 px | Hong Lou Meng (Chinese) | t1-7l9c |
| Runs from a page start that differ | 19, by at most 0.001 px | Wealth of Nations, Kindle conversion | t1-tqhs |
| Slow paragraphs with many lines | Up to 3.6 s in one step | Leaves of Grass (Song of Myself in `pre`), Hong Lou Meng, the index of The Origin of Species, verse with `br` | t1-qtde |
| Slow tables | Up to 0.75 s in one step | Plato's Dialogues, Ulysses chapter 15, Standard Ebooks plays, Roget's Thesaurus | t1-um08 |
| Unsupported features | 0 | | |

- Broken saved places. `wordStart` copies epub.js, which saves the first space-delimited word at or after the page start. Chinese text has about one space per 100 characters. At 26 pixels a page holds about 200 characters, so the next space can lie on a later page. Then the saved place opens one or two pages later. The fix changes what Bookfin saves, so t1-7l9c asks for a product choice between two designs.
- Runs that differ. The 19 runs of the Kindle Wealth of Nations hold the same text on each page. Only page heights and line positions differ, by 0.001 pixels. A resumed run sums positions from the page top, and the main run sums them from the section start. A line that ends that close to the page bottom can get a different cut.
- Slow paragraphs. `LayoutRun._lineStarts` asks the engine for one line boundary per line, and the engine builds the metrics of every line on each call. So a paragraph with n lines costs on the order of n squared, and every run that resumes inside it pays again. Song of Myself takes 1,580 ms at 20 pixels and 3,593 ms at 26 pixels in one step.
- Slow tables. A table is one flow item, so one step lays out the whole table. A run that starts inside a table lays out the whole table again. Standard Ebooks sets dialogue as tables, so Plato's Gorgias is one table of 266,000 characters: 1,086 ms for the section, and 562 ms for one run from a page in its middle.

### Approximated features

No book uses a feature that the renderer does not support. The table gives the number of books that use each approximated feature.

| Feature | Books |
| --- | --- |
| the `all` property (Gutenberg's license and header) | 48 |
| automatic hyphenation | 41 |
| `text-wrap: pretty` or `balance` | 41 |
| text moved off the page is left out | 41 |
| `vertical-align` other than `super` and `sub` | 23 |
| `inline-block` drawn as a shrink-to-fit block | 19 |
| `display: table` on a non-table drawn as a block | 16 |
| a flex column drawn as blocks | 11 |
| generated content | 8 |
| a flex row drawn as blocks | 4 |
| float drawn as a block | 4 |
| `rowspan` counted as 1 | 1 |
| `::first-letter` and `::first-line` | 1 |

`results.json` gives the sections of each feature in each book.

## Limits

- Runs from page starts. A run that starts inside a long table or a paragraph with many lines lays it out again (t1-um08, t1-qtde). With every page start, Plato's Dialogues took 67 minutes and Roget's Thesaurus did not finish in two hours. So the run limits the runs to 100 evenly spaced page starts per section. When those tickets are fixed, raise the limit (`runsPerSection` in `test/reader/epub/corpus/check.dart`). The CFI round trip still covers every page start.
- Run time. The whole run takes about three hours on a loaded host, most of it in the books of t1-um08 and t1-qtde.
- The run measures on the host only. Phone timing is separate work.
- The run draws three pages of each section. It does not compare the drawing with Chromium. `test/reader/epub/fidelity_test.dart` does that for the trial books.
- The run does not check right-to-left or vertical text. No book in the corpus uses them.
