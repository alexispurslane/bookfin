---
id: boo-b2ey
status: open
deps: []
links: []
created: 2026-11-08T18:47:22Z
type: epic
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Replace the WebView EPUB reader with the Flutter-native renderer

User decision (2026-11-08) after the boo-ju83 trial (docs/research/native-epub.md): the Flutter-native renderer becomes Bookfin's only EPUB and MOBI reader on Android, macOS, Linux, Windows and iOS. The WebView reader (packages/flutter_epub_viewer, epub.js) is removed at the end; books with features outside the subset render as well as Flutter allows, with no browser fallback. Saved places, bookmarks and history keep their EPUB CFI format. Design: docs/plans/native-epub-reader.md.

