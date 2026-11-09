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
| Blank pages | A page shows no line of text and no image. |
| A run from a page start | It cuts other pages than the main run, over the 5 pages that it cuts first. The run starts from every page start of every section. |
| Drawing | The first, middle and last page of each section draw with their images at 2.625 image pixels per layout pixel. |
| Support report | It lists the features that the renderer approximates, and the features that it does not support, by section. It is not a failure. |
| Slow items | It lists each paragraph or table whose layout step takes more than 8 ms, and the layout time per 10,000 visible characters. It is not a failure. |

## Results of 2026-11-08 and 2026-11-09

The results come from a host run under `flutter test`, with JIT code and CPU raster. Other agents loaded the machine to 4 to 40 on 10 cores. Times are therefore high and noisy. Compare them only with each other.

The renderer is main at merge 6d5afc1, after tc-z7au (hyphenation), tc-n6wv (fractional line positions) and te-4cez (split table rows) merged. The run checked 92 books in 88 minutes. Five books with pages that have no start place ran again with the blank-page check, which came later. Roget's Thesaurus ran alone, in 116 minutes. `.cache/epub-corpus/results.json` joins the three runs.

| | 412 x 671 at 20 px | 360 x 640 at 26 px |
| --- | --- | --- |
| Pages | 124,166 | 250,361 |
| Page starts whose CFI opens their own page | 124,155 of 124,155 | 250,296 of 250,358 |
| Page starts whose CFI and quote come back unchanged | all | all |
| Blank pages | 10 (five books) | 2 (two books) |
| Runs from a page start | 92,353 | 159,956 |
| Runs that cut other pages | 3 (from blank pages) | 0 |
| Sections whose runs were limited to 100 page starts | 171 | 488 |
| Paragraphs and tables over 8 ms | 986 (in 49 books) | 1,907 (in 58 books) |
| Layout time per 10,000 visible characters, median of the books | 15.2 ms | 20.5 ms |
| Layout time per 10,000 visible characters, highest | 94 ms (Roget's Thesaurus) | 269 ms (Roget's Thesaurus) |

87 of the 93 books pass every check. No check raised an exception.

| Source | Format | Books | Passed |
| --- | --- | --- | --- |
| Standard Ebooks | EPUB | 41 | 39 |
| Project Gutenberg | EPUB | 41 | 37 |
| Project Gutenberg | Kindle (KF8) | 8 | 8 |
| Bookfin's test fixture | EPUB | 3 | 3 |

### Findings

| Category | Count | Books | Ticket |
| --- | --- | --- | --- |
| Exceptions | 0 | | |
| Broken saved places | 62 page starts at 26 px | Hong Lou Meng (Chinese) | t1-7l9c |
| Blank pages from a split table row | 8 at 20 px (none after t1-6ta8) | Hamlet, Plato's Dialogues, Roget's Thesaurus | t1-6ta8 |
| Pages with only the border of an empty block | 2 at each size | The Divine Comedy, Through the Looking-Glass (Gutenberg) | t1-9vc1 |
| Runs from a page start that differ | 3 at 20 px | The blank pages of Hamlet, Dialogues and Roget's Thesaurus | t1-6ta8 |
| Slow paragraphs with many lines | Up to 3.6 s in one step (318 ms after t1-qtde) | Leaves of Grass (Song of Myself in `pre`), Hong Lou Meng, the index of The Origin of Species, verse with `br` | t1-qtde, tb-2l69 |
| Slow tables | Up to 51 s in one step (121 ms after t1-um08) | Roget's Thesaurus, Plato's Dialogues, Ulysses chapter 15, Standard Ebooks plays | t1-um08, tb-i6wg, tb-a6zd |
| Unsupported features | 0 | | |

- Broken saved places. `wordStart` copies epub.js, which saves the first space-delimited word at or after the page start. Chinese text has about one space per 100 characters. At 26 pixels a page holds about 200 characters, so the next space can lie on a later page. Then the saved place opens one or two pages later. The fix changes what Bookfin saves, so t1-7l9c asks for a product choice between two designs.
- Blank pages. A table row taller than a page splits into fragments since te-4cez. A fragment of 10 pixels with no line can become a page of its own. A run from such a page also gives it another visible-character index than the main run. t1-6ta8 found the cause: when the last lines of a split row fill a page, the cells' bottom padding became a fragment of its own, and a next row taller than a page left that fragment alone on a page. Now that padding is dropped at the break when no cell has a line left, as the space above a line is, so every fragment shows a line. After t1-6ta8, Hamlet, Plato's Dialogues and Roget's Thesaurus have no blank page and no run that cuts other pages, at both page settings, with runs from every page start.
- Border pages. A first page that overflows (an image page of 682 pixels, a table page of 704 pixels, on a 671-pixel page) pushes the 2-pixel border of a following empty block onto a page of its own. Nobody knows yet whether Chromium does the same, so t1-9vc1 starts with a comparison.
- Slow paragraphs. `LayoutRun._lineStarts` asks the engine for one line boundary per line, and the engine builds the metrics of every line on each call. So a paragraph with n lines costs on the order of n squared, and every run that resumes inside it pays again. Song of Myself takes 1,531 ms at 20 pixels and 3,553 ms at 26 pixels in one step.
- Slow tables. A table is one flow item, so one step lays out the whole table. A run that starts inside a table lays out the whole table again. Standard Ebooks sets dialogue as tables, so Plato's Gorgias is one table of 266,000 characters (706 ms at 20 pixels). Roget's Thesaurus is one table of 1.74 million characters: 8.6 s at 20 pixels and 51 s at 26 pixels.
- Hyphenation cost. Against the run before the merge, the median layout time per 10,000 characters doubled for the Standard Ebooks books, which ask for hyphenation, and fell to 0.88 times for the Gutenberg books, which do not. The note is on t0-z3m1.

### Layout steps after t1-qtde

t1-qtde finds a paragraph's line starts with one binary search per line (`Paragraph.getLineNumberAt`), not with one `getLineBoundary` call per line. It also counts the visible characters of a long text node from a count kept every 256 code units, and releases pieces once per flow item, not once per page. Each of the three costs grew with the square of a paragraph's lines. The table gives the slowest layout step of each book, in milliseconds, from the corpus run before (under heavy load) and a run of the four books after (load 5 to 15 on 10 cores).

| Book | Section, item | Before, 20 px | Before, 26 px | After, 20 px | After, 26 px |
| --- | --- | --- | --- | --- | --- |
| Leaves of Grass (Gutenberg), Song of Myself | 27, 9 | 1,531 | 3,553 | 70 | 318 |
| Hong Lou Meng | 2, 17 | 1,082 | 1,897 | 57 | 59 |
| The Origin of Species (Gutenberg), index | 17, 6 | 424 | 656 | 32 | 34 |
| Pride and Prejudice (Standard Ebooks), Darcy's letter | 36, 19 | 138 | 256 | 107 | 194 |

The rest of these steps is the engine's own work on one paragraph. On a lightly loaded host, Song of Myself takes 96 ms at 20 pixels and 143 ms at 26 pixels, of which `Paragraph.layout` takes 69 ms and 120 ms (tb-2l69). Darcy's letter lays out 20 and 32 times, once more after each word joiner that hyphenation adds (tb-a6zd). The on-demand benchmark `BOOKFIN_EPUB_STEPS=1 flutter test test/reader/epub/step_budget_test.dart` holds the step of a paragraph of 4,000 lines to less than 8 times the step of 1,000 lines. Before t1-qtde the factor was 14 (815 ms and 11,246 ms). After it the factor is 5.5 to 5.7.

### Layout steps after t1-um08

t1-um08 lays out a table one row in each unit of work, so a step stops after the row that crosses its budget. A page start inside a table names a row and a fragment of that row, so a run from it lays out no row above it. The column widths need each row measured: the run measures one row in each unit, once per table item, and other runs of the section reuse the widths. The corpus check now runs from every page start of every section.

The table gives the slowest layout step of a table, in milliseconds, from the corpus run before (under heavy load) and runs after (load 4 to 15 on 10 cores). The Ulysses numbers after come from a run of t1-um08 alone. The others come from a run with t1-6ta8 and t1-9vc1 too, which change no table step.

| Book | Section, item | Before, 20 px | Before, 26 px | After, 20 px | After, 26 px |
| --- | --- | --- | --- | --- | --- |
| Roget's Thesaurus | 1, 39 | 8,618 | 51,143 | 10 | 121 |
| Plato's Dialogues, Gorgias | 21, 458 | 706 | 1,431 | 23 | 41 |
| Plato's Dialogues, slowest table | | 706 | 1,431 | 89 | 194 |
| Ulysses (Standard Ebooks), chapter 15 | 18, 6 | 826 | 1,225 | 19 | 25 |
| Hamlet (Standard Ebooks) | 5, 24 | 86 | 119 | under 8 | under 8 |

- Two kinds of cost remain. Roget's slowest row has about 9,700 characters in 10 to 16 paragraphs, and one unit lays out a whole row (tb-i6wg). The slow rows of Plato's Dialogues are hyphenation passes: one row lays out its paragraphs 158 times (tb-a6zd).
- At 412 x 671 at 20 pixels, Roget's Thesaurus has two table steps over 8 ms (at most 10 ms), and Gorgias has six (at most 23 ms).
- With runs from every page start, the six books of the second run (Roget's Thesaurus, Plato's Dialogues, Hamlet, Moby-Dick, The Divine Comedy, Through the Looking-Glass) took 15 minutes together. Before, Roget's Thesaurus alone took 116 minutes with runs from 100 page starts per section.
- The on-demand benchmark `test/reader/epub/step_budget_test.dart` lays out a dialogue table of 1,000 rows. Before t1-um08, its slowest step took 248 ms, a run from a page start in its middle took 277 ms to its first page, and a place in a late row took 537 ms to open. After it, they take 5 to 9 ms, under 1 ms and under 1 ms.

### The run before the merge

The same corpus ran first on the renderer at 0bc7a08, before the merge. 90 of 92 books passed. It found the broken places of Hong Lou Meng (53 at 26 pixels) and 19 runs of the Kindle Wealth of Nations that differed by 0.001 pixels (t1-tqhs). tc-n6wv fixed the second. That run had no blank-page check.

### Approximated features

No book uses a feature that the renderer does not support. The table gives the number of books that use each approximated feature.

| Feature | Books |
| --- | --- |
| the `all` property (Gutenberg's license and header) | 48 |
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

- Runs from page starts. A run that starts inside a paragraph lays out the whole paragraph again, so that the orphans and widows rules see it. Since t1-qtde and t1-um08, a run that starts inside a table lays out only its own row, and the run starts from every page start.
- Run time. Before t1-qtde and t1-um08, the run without Roget's Thesaurus took about 90 minutes on a loaded host, and Roget's Thesaurus alone took about two hours. Nobody ran the whole corpus after them yet.
- The run measures on the host only. Phone timing is separate work.
- The run draws three pages of each section. It does not compare the drawing with Chromium. `test/reader/epub/fidelity_test.dart` does that for the trial books.
- The run does not check right-to-left or vertical text. No book in the corpus uses them.
- Automatic hyphenation counts as approximated only in a language without hyphenation patterns. The renderer hyphenates English since tc-z7au, and no corpus book asks for hyphenation in another language.
