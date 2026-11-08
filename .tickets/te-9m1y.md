---
id: te-9m1y
status: open
deps: []
links: []
created: 2026-11-08T18:29:15Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Keep Standard Ebooks style sheets that declare a CSS namespace

boo-ju83 found that Publication's style sheet sanitizer (packages/flutter_epub_viewer/lib/publication.dart, _css) empties any sheet whose text contains @namespace. Every Standard Ebooks book starts core.css, local.css and se.css with '@namespace epub "http://www.idpf.org/2007/ops";', so the WebView reader shows every Standard Ebooks book with no book styles: no small-caps headings, no verse indents, no centered title blocks. Allow a plain @namespace rule (a prefix and a quoted URL) and keep the rest of the sanitizer. Also seen in the boo-ju83 trial: with those sheets restored, the scrub deck's page drawing (reader.js drawPage) failed in Chromium with 'EncodingError: The source image cannot be decoded.' for every Standard Ebooks section; find the cause before the sheets come back.

## Acceptance Criteria

A Standard Ebooks EPUB keeps its three sheets after admission, a test proves it, and a scrub deck page of such a book draws.

