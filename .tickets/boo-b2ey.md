---
id: boo-b2ey
status: in_progress
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


## Notes

**2026-11-08T19:24:02Z**

Design written: docs/plans/native-epub-reader.md. 22 tickets under this epic, ordered with tk dep. Start: tc-bsen and tc-acl5 (wave 1). Two tracks follow: the renderer track (tc-txyr, tc-n6wv, tc-z7au, tc-cl77) and the navigation track (tc-tjtc, tc-mxfp, tc-1iap, tc-zevb, tc-1yif, tc-fz4n, tc-iwqp). tc-pshi must merge before tc-rap6 removes epub.js. tc-406m (footnote links) waits for the user's choice between the two options in the design's 'Product fork for the user'.
