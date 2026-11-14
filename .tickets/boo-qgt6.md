---
id: boo-qgt6
status: closed
deps: []
links: []
created: 2026-11-14T16:43:04Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Show Listen and Read as two equal buttons on the book page, each with a download icon until its edition is downloaded


## Notes

**2026-11-14T17:02:38Z**

BookActions shows Listen and Read as two Expanded FilledButtons through one EditionAction widget. A downloaded edition shows its icon (PlayStateIcon / menu_book) and opens; otherwise the button shows the edition's download state (download arrow, progress ring, Wi-Fi off, retry) and reports its next DownloadAction. The round DownloadButton is gone from the book page; removal stays in the edition panel and Downloads. The label is always Listen (no Resume), as the user asked. Download icon, tooltip and share helpers in downloads/screen.dart are public and shared. Tests: 7 behaviors in test/catalog/book_page_test.dart; 5 failed on the old code for the right reasons. Checked on a private emulator: Listen play icon + Read download icon for First Frost; a tap on Read downloaded the ebook, the icon turned into the book, and Read opened it. 1406 tests in catalog, app, downloads and playback pass.
