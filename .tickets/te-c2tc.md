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

