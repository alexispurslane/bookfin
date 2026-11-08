---
id: tc-z7au
status: in_progress
deps: [tc-n6wv]
links: []
created: 2026-11-08T19:23:13Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-b2ey
---
# Hyphenate text that asks for it

Goal: text whose CSS asks for hyphens: auto breaks long words at line ends with a hyphen, as Chromium does.

Design section: "Coverage beyond the trial / Hyphenation".

Files: lib/reader/epub/hyphenate.dart (new), lib/reader/epub/hyphenation_en.dart (new, pattern data), lib/reader/epub/prepare.dart, lib/reader/epub/layout.dart, assets/licenses/reader/ (the pattern license and its manifest.json entry), test/reader/epub/hyphenate_test.dart.

Rules:
- First find out whether Flutter's paragraph draws a hyphen at a soft hyphen break: lay out a word with U+00AD in a narrow width and inspect the line. If it does, use it. If not, layout adds a hyphen marker decoration at the end of each line that ends at a soft hyphen (paint already draws marker decorations).
- Liang's algorithm with the TeX hyph-en-us and hyph-en-gb patterns from the hyph-utf8 project, pinned by version and SHA-256 in a comment.
- Language: lang, then xml:lang, then the package's dc:language (passed in through SectionSource).
- Words under 5 letters do not break. Keep at least 2 letters before a break and 3 after.
- prepare inserts the soft hyphens into styled runs. The text map skips them, so places, quotes, search and copy never see them.
- Keep the signatures from tc-nang.

## Design

docs/plans/native-epub-reader.md (epic boo-b2ey). Read the sections named in the description. The design decides the owners, interfaces and order. Ask the orchestrator before changing them.

## Acceptance Criteria

- Known words from the TeX English test set break where the patterns allow (for example hy-phen-ation).
- Text with hyphens: auto and lang en breaks long words at line ends and shows a hyphen. Text without it never breaks inside a word.
- Places, quotes and copied text contain no soft hyphens.
- E3's properties still hold.


## Notes

**2026-11-08T23:10:19Z**

Flutter breaks at U+00AD but draws no hyphen. Layout writes U+2010 in place of each soft hyphen that ends a line (after a fit check) and lays the paragraph out again, so justified lines end at the hyphen as in Chromium; a hyphen that does not fit becomes U+2060. This replaces the ticket's marker-decoration fallback, which would hang the hyphen past the right edge of justified text. xml:lang wins over lang (HTML rule, as :lang() already did). Capitalized English words do not break (Chromium). dc:language goes through SectionSource.language; the page source does not fill it yet (t0-2yee). fidelity_test and saved_places_test (downloaded books) compare with hyphenation off, as epub.js recorded; saved_places_test adds a hyphenated check. Layout cost: t0-z3m1.
