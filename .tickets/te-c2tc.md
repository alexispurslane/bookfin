---
id: te-c2tc
status: open
deps: []
links: [t3-5o5r]
created: 2026-11-09T23:25:19Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Give every test EPUB builder a fixed entry time

Found in boo-02sx. The archive package stamps each ZIP entry with the time of the encode, which a ZIP file keeps to two seconds. So a test book built twice can get other bytes and another digest, and the reader then refuses a place saved in the first build. This made the time_left_test speed store test flaky under load. session_native_test.dart now builds its books through one helper with a fixed time. These builders still stamp the current time: epub() in test/reader/publication_test.dart, book() in test/reader/epub/page_source_test.dart, test/reader/epub/admission_test.dart, test/reader/epub/epubjs_fixtures.dart, test/reader/epub/corpus/book.dart and tool/showcase_media.dart. Give them a fixed time too, or share one builder.

## Inventory after the t3-5o5r investigation — 2026-11-13

t3-5o5r fixes only `epub()` in `test/reader/publication_test.dart`. A
controlled two-second change of the archive entry times reproduced its reader
restart assertion failure after a successful save. The payload hashes were
equal, but the original-file digests differed. Holding the entry times equal
restored the place. Production source-identity checks remain unchanged.
The exact schedules of the historical failures remain unknown.

The shared helper now gives every entry a fixed local calendar time.
`test/reader/session_native_test.dart` already fixes its entry times.
The following builders still construct new entries without a fixed time:

- `test/reader/epub/page_source_test.dart`: `book()`.
- `test/reader/epub/admission_test.dart`: `archive()`.
- `test/reader/epub/epubjs_fixtures.dart`: replacement entries.
- `test/reader/epub/corpus/book.dart`: `madeUpEpub()`.
- `tool/showcase_media.dart`: generated showcase books.
- `test/reader/epub/damaged_chapters_test.dart`: `_book()`; newly inventoried.
- `test/reader/epub/section_styles_test.dart`: `styledBook()`; newly inventoried.

This inventory comes from searching `ArchiveFile` and `lastModTime` under
`test/reader` and in `tool/showcase_media.dart`; the source evidence is in
`docs/evidence/t3-5o5r/source-audit.txt.gz`. The `showcase()` wrapper in
`admission_test.dart` and `showcaseBooks()` in `corpus/book.dart` already
override the encoder's modification time; those paths are fixed. These seven
remaining builders were not changed by t3-5o5r. This wider ticket remains open; the parent owns integration and
closure.
