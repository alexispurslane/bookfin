---
id: tc-4f3q
status: in_progress
deps: [tc-nang, tc-sqp7]
links: []
created: 2026-11-08T19:23:13Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-b2ey
---
# Run the native renderer over a 50 to 100 book corpus on demand

Goal: an on-demand test over 50 to 100 public-domain books that finds exceptions, broken saved places, approximations and slow paragraphs.

Design section: "Testing / Corpus test".

Files: tool/reader/epub_corpus.json (new), tool/reader/fetch_epub_corpus.py (new), test/reader/epub/corpus_test.dart (new), test/reader/epub/corpus/ (the support report, moved from test/reader/epub/trial/support.dart), docs/research/native-epub-corpus.md (new).

Rules:
- The list gives id, title, source URL, SHA-256, format (epub or azw3) and why it is in. About 40 Standard Ebooks books, about 40 Project Gutenberg EPUB 3 books with images (poetry, plays, tables, illustrated children's books, a reference book), about 8 Gutenberg Kindle (azw3) files for MOBI through libmobi, and the 10 trial books.
- The fetch script runs in the dev shell, downloads into .cache/epub-corpus/ (git ignores .cache) and checks each SHA-256.
- The test runs only with BOOKFIN_EPUB_CORPUS=1. It writes .cache/epub-corpus/results.json.
- Per book, the test does these checks:
  - The book admits. A MOBI converts first.
  - Every section prepares and lays out at 412 x 671 at 20 pixels and at 360 x 640 at 26 pixels, with no exception.
  - Every page start's CFI opens its own page.
  - It lists the approximations from the support report, the paragraphs whose shaping takes over 8 ms, and the layout milliseconds per 10,000 visible characters.

File rule: tc-pshi runs at the same time and edits test/reader/epub/trial/fidelity_test.dart and book.dart. Do not edit those two. Move support.dart out of test/reader/epub/trial and replace trial/corpus_test.dart with test/reader/epub/corpus_test.dart.

## Design

docs/plans/native-epub-reader.md (epic boo-b2ey). Read the sections named in the description. The design decides the owners, interfaces and order. Ask the orchestrator before changing them.

## Acceptance Criteria

- The list has at least 50 public-domain books with pinned SHA-256 values.
- A full host run has no exception and a 100 percent round trip of page starts, or each failure has its own ticket.
- docs/research/native-epub-corpus.md holds the summary table and the commands.


## Notes

**2026-11-09T04:25:03Z**

Built. tool/reader/epub_corpus.json pins 93 books (41 Standard Ebooks, 41 Gutenberg EPUB 3, 8 Gutenberg KF8, 3 showcase) by SHA-256 and size; tool/reader/fetch_epub_corpus.py (tests: tool/reader/test_fetch_epub_corpus.py) downloads them one at a time with a 3-second pause, and --pin records new books. test/reader/epub/corpus/ holds the book (TrialBook moved and renamed CorpusBook; it reads Publication.bookStyles, imageSizes and language as PageSource does), the support report (moved), the list and the per-book checks; test/reader/epub/corpus_test.dart replaces trial/corpus_test.dart and benchmark.dart and keeps their checks (support, CFI round trip, stepped run, runs from page starts, drawing). Departures: (1) a section with more than 100 page starts runs from 100 evenly spaced ones, because t1-um08 and t1-qtde make every run inside a long table or paragraph lay it out again; (2) the run also reports blank pages, which the round trip skipped; (3) the support report counts automatic hyphenation only where the language has no patterns, since tc-z7au. Findings and tickets: docs/research/native-epub-corpus.md (t1-7l9c, t1-6ta8, t1-9vc1, t1-qtde, t1-um08; t1-tqhs fixed by tc-n6wv).
