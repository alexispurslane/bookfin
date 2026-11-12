---
id: boo-3huo
status: closed
deps: []
links: []
created: 2026-11-12T12:41:26Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Load a book's own font only for characters that the reader font lacks

User decision 2026-11-12: "I agree with the lazy font loading planned by the way. I definitely want that." It follows boo-iv7q (always draw in the reader font) and replaces t0-sx00.

Model. Admission (at download completion, in the worker) already reads every chapter. During that pass it finds runs whose style names one of the book's embedded faces and checks each character against the reader font's character coverage, which is known ahead because the font ships with the app. A face is needed by a chapter when it covers a character of such a run that the reader font lacks. The admitted record keeps only the needed font files and, per chapter, the needed faces. Most books need none.

At open nothing new runs for a book that needs no face. A chapter that needs faces loads only those faces (registration on the UI isolate, conversion off it) before it lays out, and only those characters draw in the book's face; all other text stays in the reader font. The kept last page is still shown in the first frame unless the shown page uses a book face; key it on the face files if that is cheap, else skip only those pages.

Known limits, accepted: ornament fonts that map shapes onto ordinary letters are not detected, and only the reader font's coverage is checked, not Android's system fonts.

Costs: a new Publication.revision, so every downloaded book is admitted again once and its page maps are rebuilt. t0-sx00 (drop unused font files from the record) is folded in here.


## Notes

**2026-11-12T13:11:22Z**

Built on t3/793df8bd. Admission (prepare.dart neededFaces, publication.dart _sectionFaces) compares each font file's cmap with a generated table of the reader font's coverage (lib/reader/epub/reader_coverage.dart, 918 code points in 150 ranges, written by tool/reader/reader_coverage.dart; a test fails when it is stale). Control characters and default ignorable code points never need a face. Publication.sectionFaces names the needed faces per section; the record keeps only their font files; Publication.revision 4 -> 5. PageSource registers a section's faces (BookFonts, conversion in a worker) while its worker prepares it. A run that a needed face styles keeps the reader font as its family and puts the face first in its fallback list. KeptPage.encode refuses a page that names a face; the kept page key now names Publication.revision. Fixture outfit-star.woff from tool/reader/book_font_fixture.py. Measured admission cost (host, JIT, load ~18-24): books without fonts unchanged; 30-section book with an unneeded own font +1-2 ms; same book with one needed character +4-5 ms.

**2026-11-12T13:15:02Z**

Merged to main at b87dad59. Orchestrator check on main: format clean, analyze clean, 3021 passed, 25 skipped. Kept-page option A (skip any page that uses a needed face) kept as built; option B (check the page's characters) only if a real book shows the problem.
