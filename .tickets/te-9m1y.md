---
id: te-9m1y
status: closed
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


## Notes

**2026-11-08T19:23:53Z**

Absorbed by tc-acl5 and tc-nh0b (epic boo-b2ey). Do not fix this in the sanitizer. The publication identity is a hash of every admitted file, so a changed sheet changes the identity of every Standard Ebooks book, and ReaderDocument.restore then refuses every saved place and bookmark of those books. Instead, admission keeps each sheet's original text beside the identity (tc-acl5), and the native CSS parser reads it (tc-nh0b). The reader.js drawPage EncodingError goes away with epub.js (tc-rap6). Close when tc-nh0b merges.

**2026-11-08T20:15:52Z**

Closed by the tc-nh0b merge (c3210d8): the Standard Ebooks core.css test passes with @namespace and epub|type.
