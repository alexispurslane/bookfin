---
id: tc-zevb
status: open
deps: [tc-mxfp]
links: []
created: 2026-11-08T19:23:12Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-b2ey
---
# Open EPUB and MOBI books in the native pager from the reader session

Goal: the session creates, attaches and disposes the pager, and exposes it to the screen. DocumentNavigator loses configure. The chapter arrows use the shown page's end. This absorbs t6-0cjf.

Design sections: "Navigation" (how the session uses the pager), "Places / Data safety".

Files: lib/reader/document.dart, lib/reader/session.dart, lib/reader/book_map.dart, lib/reader/pdf_viewport.dart, lib/reader/epub/pager.dart (configure only), test/reader/session_native_test.dart (new), test/reader/book_map_test.dart.

Changes:
- open: for an EpubDocument (EPUB and MOBI), create EpubPager(document, initial: initialAddress, onPlace: (address) => acceptAddress(token, address), onWarning: (message) => warn(token, message)). Then attachDocument(token, pager, contents). contents is publication.contents. If that list is empty, it is one 'Chapter N' entry per linear spine item (reader.js rule).
- Add EpubPager? get pager, on the documentChanges signal.
- _clear disposes the pager.
- moveChapter forward goes to the first chapter that starts after the shown page's start and at or after its end (EpubAddress.location.end). Back stays as it is.
- Remove configure from DocumentNavigator, EpubNavigator, PdfViewport and EpubPager.
- Until tc-1yif merges, the Android screen still builds the WebView viewport, whose attach replaces the pager as navigator. That is expected. tc-rap6 removes the WebView path.

## Design

docs/plans/native-epub-reader.md (epic boo-b2ey). Read the sections named in the description. The design decides the owners, interfaces and order. Ask the orchestrator before changing them.

## Acceptance Criteria

- Session tests with the real pager on fixture EPUBs, and on a converted MOBI where the host has libmobi (skip with a reason otherwise): open, turn, bookmark, open a bookmark, search, open a hit, a contents entry, the chapter arrows.
- Opening at a saved place adds no changed resume to the store (a store spy).
- A text size change adds no record.
- A place saved at the last turn opens on the same page in a new session.
- A place with a wrong quote keeps its old record until a move.
- Next chapter skips a chapter that starts in the middle of the shown page (t6-0cjf), with a BookMap test.
- checkInvariants of the session passes after each step.

