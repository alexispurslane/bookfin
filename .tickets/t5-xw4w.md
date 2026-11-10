---
id: t5-xw4w
status: closed
deps: []
links: []
created: 2026-11-10T02:12:49Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Build each section's DOM from package:xml's events, without its tree

Found in tf-focn (docs/research/epub-first-page-timing.md). DomSection.parse builds package:xml's tree of nodes and then converts it into Bookfin's DOM. Reading package:xml's events straight into Bookfin's DOM, with the same tokenizer and the same checks (validateNesting, validateDocument), accepts and rejects the same documents with the same exceptions and saved about 5 percent of Keats' section 2 prepare. With t7-49gt, the part worker still parses the whole section, so the parse is a larger share of the time to a page deep in a large section.

## Acceptance Criteria

The corpus prepare hashes (BOOKFIN_EPUB_CORPUS_PREPARE with tool/reader/compare_corpus_prepare.py) equal the base's for every corpus book in all three page settings, the trial and corpus tests pass, and malformed documents fail with package:xml's exceptions.


## Notes

**2026-11-10T03:25:38Z**

Results (host, flutter test on the Mac, dom.dart before and after the patch alternated on 752a2ee in three paired corpus prepare rounds). Hashes: 0 differences over 93 books in all three page settings (13,719 prepared sections, 0 errors), and all six runs had the same hashes. Malformed documents: dom_test compares the DOM with package:xml's tree, and 10 malformed documents fail with equal exceptions. Times, median of the three rounds, each the fastest of 3 prepares: Keats' section 2 209.5 ms before, 183.6 ms after (0.88). The corpus total 11,836 ms before, 11,020 ms after (0.93). The median ratio over all sections 0.94, over the sections of 10 ms or more 0.95. On this commit the trial tests (BOOKFIN_EPUB_TRIAL=1) passed 96, corpus_test (BOOKFIN_EPUB_CORPUS=1) passed 94.
