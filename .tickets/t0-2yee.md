---
id: t0-2yee
status: in_progress
deps: []
links: []
created: 2026-11-08T22:55:12Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Pass the package's dc:language to prepare for hyphenation

tc-z7au added SectionSource.language: the language of text whose elements name none, as the fallback for hyphenation after xml:lang and lang. Nothing fills it yet. Publication does not expose the package's dc:language, and PageSource._prepareInWorker (lib/reader/epub/page_source.dart, owned by te-k1l3 at the time) builds SectionSource without it. Add Publication.language beside bookStyles (outside the identity, so saved places do not move), and pass it to SectionSource in the page source. Books whose XHTML names no lang or xml:lang then hyphenate when their CSS asks for hyphens: auto.

## Acceptance Criteria

A section without lang or xml:lang, in a package whose dc:language is en, hyphenates text that asks for hyphens: auto. Publication.admit keeps its identity byte for byte.


## Notes

**2026-11-08T23:42:13Z**

Publication.language: the package's first dc:language that is not blank, trimmed, read from the admitted package document (opf) at the end of admission. It sits beside bookStyles, outside the identity: the identity input and Publication.policy did not change, and all 13 identity pins in admission_test pass (3 showcase, 3 committed fixtures, 7 trial books). page_source.dart passes it to SectionSource.language and changes nothing else. Every trial book reports a language (en, en-US or en-GB).
