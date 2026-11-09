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
| Blank pages | A page draws nothing: no line of text, no image and no rule. A page that draws only a rule is not blank, because Chromium shows such pages too (see "Border pages"). |
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
| Pages with only the border of an empty block | 2 at each size, as in Chromium | The Divine Comedy, Through the Looking-Glass (Gutenberg) | t1-9vc1 |
| Runs from a page start that differ | 3 at 20 px | The blank pages of Hamlet, Dialogues and Roget's Thesaurus | t1-6ta8 |
| Slow paragraphs with many lines | Up to 3.6 s in one step (318 ms after t1-qtde) | Leaves of Grass (Song of Myself in `pre`), Hong Lou Meng, the index of The Origin of Species, verse with `br` | t1-qtde, tb-2l69 |
| Slow tables | Up to 51 s in one step (121 ms after t1-um08) | Roget's Thesaurus, Plato's Dialogues, Ulysses chapter 15, Standard Ebooks plays | t1-um08, tb-i6wg, tb-a6zd |
| Unsupported features | 0 | | |

- Broken saved places. `wordStart` copies epub.js, which saves the first space-delimited word at or after the page start. Chinese text has about one space per 100 characters. At 26 pixels a page holds about 200 characters, so the next space can lie on a later page. Then the saved place opens one or two pages later. The fix changes what Bookfin saves, so t1-7l9c asked for a product choice between two designs. The user chose design B: a page saves its first visible character. After that change, every page start of Hong Lou Meng opens its own page: 2,790 of 2,790 at 360 × 640 at 26 pixels, and 1,368 of 1,368 at 412 × 671 at 20 pixels.
- Blank pages. A table row taller than a page splits into fragments since te-4cez. A fragment of 10 pixels with no line can become a page of its own. A run from such a page also gives it another visible-character index than the main run. t1-6ta8 found the cause: when the last lines of a split row fill a page, the cells' bottom padding became a fragment of its own, and a next row taller than a page left that fragment alone on a page. Now that padding is dropped at the break when no cell has a line left, as the space above a line is, so every fragment shows a line. After t1-6ta8, Hamlet, Plato's Dialogues and Roget's Thesaurus have no blank page and no run that cuts other pages, at both page settings, with runs from every page start.
- Border pages. A first page that overflows (an image page of 682 pixels, a table page of 704 pixels, on a 671-pixel page) pushes the 2-pixel border of a following empty block onto a page of its own. t1-9vc1 compared both sections with the WebView reader: epub.js in headless Chromium at 412 x 671 pixels with 20-pixel text. Chromium also cuts two pages for each section, and its second page shows only a thin rule at its top. So the native cut matches the WebView reader and stays. The blank-page check now counts only pages that draw nothing, and both books pass it.
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

### Layout steps after tb-a6zd

tb-a6zd marks the hyphens of a paragraph a part of about 256 code units at a time, built from a line's start. A word joiner then lays out only that part again, not the whole paragraph. The whole paragraph is laid out once at the end, and again only when a mark changes. After a mark changes there, the parts go on from the line before the changed mark. The table gives the slowest layout steps, in milliseconds, from the main run on the host before and after (load 5 to 16 before, 8 to 12 after, on 10 cores).

| Book | Section, item | Before, 20 px | Before, 26 px | After, 20 px | After, 26 px |
| --- | --- | --- | --- | --- | --- |
| Pride and Prejudice (Standard Ebooks), Darcy's letter | 36, 19 | 105 (20 layouts) | 187 (32 layouts) | 16 | 15 |
| Plato's Dialogues, slowest paragraph | 30, 184 | 125 (20 layouts) | 126 (17 layouts) | 26 | 34 |

- The on-demand benchmark `step_budget_test.dart` lays out a justified paragraph of about 15,000 characters of long words. With hyphens, its step took 669 ms before and 14 to 17 ms after. Without hyphens it takes 4 to 6 ms.
- The paragraphs of Plato's Dialogues have many word joiners, so their parts cost 3 to 6 times one layout of the paragraph.
- A part measures its lines with less float error than the whole paragraph. Over 47 corpus books at both page settings, 5 of 4,822 section layouts changed, all at 26 pixels. `docs/plans/native-epub-reader.md` ("Hyphenation") explains why each old line was wrong.

### Layout steps after tb-2l69

tb-2l69 lays out a long paragraph with hard breaks in segments: whole lines that end after a hard break, at least 1,024 code units each. Each segment is a unit of work, so a step stops between segments. The run keeps the number of lines before each segment, so a run from a page start or a search for a place inside the paragraph lays out only the segment that holds it. The table gives the slowest layout unit, in milliseconds, from the main run on the host before and after (load 6 to 16 on 10 cores).

| Book | Section, item | Before, 20 px | Before, 26 px | After, 20 px | After, 26 px |
| --- | --- | --- | --- | --- | --- |
| Leaves of Grass (Gutenberg), Song of Myself | 27, 9 | 79 | 122 | under 4 | under 4 |
| The Origin of Species (Gutenberg), index | 17, 6 | 23 | 19 | 6 | under 4 |

- The corpus run of Leaves of Grass (EPUB and Kindle) and The Origin of Species lists no paragraph over 8 ms at either page setting, and all three pass every check.
- The on-demand benchmark lays out 2,000 lines of verse in one `pre` element. Its slowest step with a budget of 4 ms took 23 ms before and 4.3 ms after. A run from a page start three quarters in cuts its first page in 0.5 ms. A search for a place near the end, in a section that no run laid out, takes steps of at most 4.3 ms.
- A page dump of 47 corpus books at both page settings is the same before and after, for all 4,822 section layouts.

### Layout steps after tb-i6wg

tb-i6wg lays out a table row one flow item of a cell in each unit of work, or one segment of a long paragraph. The row keeps its laid-out cells until the last one is done, because the row's fragments need the content of all its cells. Then the row adds its slices in the same unit. The table gives the slowest table unit, in milliseconds, from the main run on the host before and after (load 8 to 12 on 10 cores).

| Book | Section, item | Before, 20 px | Before, 26 px | After, 20 px | After, 26 px |
| --- | --- | --- | --- | --- | --- |
| Roget's Thesaurus | 1, 39 | 7 to 12 | 7 to 12 | under 6 | under 6 |
| Plato's Dialogues, row of 22 paragraphs | 30, 1244 | 110 | 212 (158 layouts) | 6 | 8 |
| Plato's Dialogues, slowest table unit | 30, 1292 | not measured | not measured | 13 | 16 |

- The ticket's 121 ms for Roget's slowest row came from a cold corpus run under heavy load. In a warm run on a lighter host, the row took 7 to 12 ms before tb-i6wg.
- The slowest table unit of Plato's Dialogues is now one paragraph of a cell, a hyphenated paragraph of row 14 of item 1292. Its cost is the cost of one paragraph (see "Layout steps after tb-a6zd").
- The on-demand benchmark `step_budget_test.dart` lays out a table of 30 rows, each with 16 paragraphs in one cell. Its slowest step with a budget of 4 ms took 8.2 ms before and 4.3 to 5.4 ms after.
- The corpus run times each section once, from cold caches, so its numbers are higher. It lists no table unit of Roget's Thesaurus over 8 ms at either page setting. The slowest table unit of Plato's Dialogues takes 17 ms at 20 pixels and 18 ms at 26 pixels. After t1-um08 they took 89 and 194 ms. Both books pass every check, with runs from every page start.
- A page dump of 48 corpus books at both page settings is the same before and after, for all 4,886 section layouts.
- Roget's Thesaurus still has slow paragraphs. Each section of its index is one justified paragraph of up to 54,000 characters with no hard break, so it is one unit of work: up to 71 ms at 20 pixels and 76 ms at 26 pixels in the corpus run (tb-3xvr).

### Layout steps after tb-o242 and tb-3xvr

tb-o242 judges a hyphen near the end of its line by two measures: the line alone and the line with its hyphen. So fewer hyphens are misjudged. A misjudged hyphen cost one more layout of the whole paragraph and new marks to its end. tb-3xvr lays out every long paragraph in segments of whole lines that end at a cut, with or without hard breaks (see `docs/plans/native-epub-reader.md`, "Steps"). The on-demand tool `test/reader/epub/corpus_steps_test.dart` timed the main run of every section of the 93 corpus books before (eb75d1c) and after. Both runs ran at the same time on the host (load 5 to 13 on 10 cores). Each unit of work counts at its fastest of three runs. The table gives the longest step of the page source's budget of 4 ms, in milliseconds. It lists each book with a step over 10 ms before or over 8 ms after.

| Book | Before, 20 px | Before, 26 px | After, 20 px | After, 26 px |
| --- | --- | --- | --- | --- |
| Ulysses (Standard Ebooks) | 24.1 | 39.5 | 5.5 | 5.5 |
| Roget's Thesaurus (Gutenberg) | 38.1 | 39.2 | 8.7 | 9.2 |
| The Wealth of Nations (Standard Ebooks) | 36.0 | 32.4 | 5.4 | 5.6 |
| Plato's Dialogues | 25.2 | 33.3 | 19.6 | 18.3 |
| Hong Lou Meng (Gutenberg) | 26.5 | 26.7 | 5.6 | 5.6 |
| Crime and Punishment | 16.1 | 17.8 | 5.2 | 5.3 |
| The Divine Comedy | 14.6 | 10.7 | 5.4 | 6.0 |
| Pride and Prejudice | 14.1 | 8.4 | 5.2 | 5.5 |
| The Adventures of Sherlock Holmes | 5.3 | 13.9 | 8.0 | 9.5 |
| A Tale of Two Cities | 12.3 | 9.2 | 6.1 | 6.0 |
| The Origin of Species (Standard Ebooks) | 9.2 | 11.7 | 5.4 | 5.5 |
| Heart of Darkness | 10.2 | 11.4 | 5.2 | 5.4 |
| The Wealth of Nations (Gutenberg, Kindle) | 10.9 | 9.5 | 4.4 | 4.4 |
| Household Management (Gutenberg) | 9.5 | 10.7 | 4.7 | 4.7 |
| Emma | 7.5 | 10.1 | 5.4 | 5.3 |
| Poe's short fiction | 8.2 | 9.0 | 7.1 | 11.7 |

- Over 186 book and page settings pairs, 23 had a step over 10 ms before and 3 after. The longest step fell from 39.5 ms to 19.6 ms.
- The slowest unit left is a table row measure of Plato's Dialogues (section 30, item 1244): 17 to 19 ms before and after. A row measure lays out every paragraph of the row's cells at an infinite width in one unit, and this row has 22 paragraphs (t2-wcab).
- The after steps of Sherlock Holmes and Poe were pauses of the host. Their slowest units take under 3 ms when timed alone, before and after.
- Timed alone and warm, a segment of Roget's index (section 76, item 12) takes 3 to 6 ms. Each segment builds about 110 style runs. The whole paragraph took 43 to 56 ms warm and up to 119 ms cold. Darcy's letter (Pride and Prejudice, 36, 19) and the slowest paragraph of Plato's Dialogues (30, 184) have no unit over 3 ms. They took 9 to 26 ms and 26 to 29 ms before.
- The text engine keeps paragraphs that it shaped, and it serves the same text and styles again from that cache. So the second and third runs of a section can take less time than a first layout. The old code gains more from this, because it makes fewer distinct paragraphs. A first, cold layout of a hyphenated paragraph of 15,000 characters takes 22 to 28 ms in total, before and after. Its slowest unit took 22 to 28 ms before and takes 1.6 to 1.8 ms after.
- The on-demand benchmark `step_budget_test.dart` now lays out a new text in each timed run, for its hyphenated paragraph and its index paragraph. A cold index paragraph of 60,000 characters in 6,000 style runs has steps of at most 5.0 ms with a budget of 4 ms. A cold segment of the hyphenated paragraph takes 2.1 ms, 3.5 to 4.2 times a plain segment.
- tb-o242 counts the code units that runs give the text engine. Darcy's letter laid out 4.2 times its code units at 20 pixels and now 2.3 times. Plato's 30, 184 laid out 4.0 and 5.4 times and now 2.2 times.

The page dumps compare by line, to a tenth of a pixel, because a paragraph now draws in other pieces. Of 9,146 section layouts, 324 differ.

- 285 sections of Standard Ebooks books changed hyphens. In 431 changed lines, the old hyphen was too wide by the line alone, by 0.01 to 0.68 pixels. In 132 changed lines, the old word joiner's hyphen fit both alone and drawn.
- 36 sections changed a line at the very limit of its width. 32 of them are in Gutenberg books (22 in Hong Lou Meng), and 4 in Standard Ebooks books. A segment measures with less float error than the whole paragraph, so its line breaks otherwise. The longer of the two lines passes the width by at most 0.0098 pixels, and the new line is sometimes the longer one. So these changes are not proved wrong before.
- 3 sections of Calculus Made Easy differ only in where a line's text sits, by the rounding to a tenth of a pixel.

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

- Runs from page starts. A run that starts inside a paragraph lays out the whole paragraph again, so that the orphans and widows rules see it. Since t1-qtde and t1-um08, a run that starts inside a table lays out only its own row, and the run starts from every page start. Since tb-2l69 and tb-3xvr, a run that starts inside a long paragraph lays out only the segment that holds its start line, once another run found the segments before it.
- Run time. Before t1-qtde and t1-um08, the run without Roget's Thesaurus took about 90 minutes on a loaded host, and Roget's Thesaurus alone took about two hours. Nobody ran the whole corpus after them yet.
- The run measures on the host only. Phone timing is separate work.
- The run draws three pages of each section. It does not compare the drawing with Chromium. `test/reader/epub/fidelity_test.dart` does that for the trial books.
- The run does not check right-to-left or vertical text. No book in the corpus uses them.
- Automatic hyphenation counts as approximated only in a language without hyphenation patterns. The renderer hyphenates English since tc-z7au, and no corpus book asks for hyphenation in another language.
