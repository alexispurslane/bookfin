---
id: t1-z0zj
status: open
deps: []
links: []
created: 2026-11-08T04:08:43Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# The mini player in the reader shows a generated cover instead of the book's cover

Seen on emulator-5554 with tool/showcase_fixture.dart (commit after 53d0c03). First Frost has a Jellyfin cover, and the mini player shows it on the Library, Downloads and Listening tabs. In the EPUB and PDF reader, the same mini player shows the generated gold cover for the title First Frost instead. Expected: the same cached cover everywhere. See docs/screenshots/reader-epub.png.

