---
id: t1-2svj
status: open
deps: []
links: []
created: 2026-11-08T20:13:41Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Create the trial books directory before the corpus test writes the showcase books

Found in tc-nh0b. With BOOKFIN_EPUB_TRIAL=1 in a checkout without .cache/epub-trial/books, corpus_test.dart setUpAll fails: _writeShowcase calls writeAsBytesSync on .cache/epub-trial/books/showcase-frost.epub and gets PathNotFoundException. Create the directory (recursive) first, as _write does for the results.

## Acceptance Criteria

BOOKFIN_EPUB_TRIAL=1 flutter test test/reader/epub/trial/ passes in a fresh worktree.

