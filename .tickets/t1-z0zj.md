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


## Notes

**2026-11-08T16:46:19Z**

boo-bz3x fixes this: the reader page pushed from the book page now wraps ReaderScreen in services.coverScope, so the audiobook's round cover button in the reader dock shows the cached Jellyfin cover. Seen on the bookfin-bz3x emulator with First Frost. The mini player is no longer in the reader. Ready to close with boo-bz3x.
