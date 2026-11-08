---
id: tc-zevb
status: closed
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


## Notes

**2026-11-08T22:04:24Z**

From tc-mxfp: the pager opens at the first present(), so the session can call attachDocument at once; display/contents/seek before the first present wait for it, and move before it does nothing. The constructor has an extra optional hop (search batches; default compute). configure is a no-op until this ticket removes it. A failed open calls onWarning with the WebView's displayerror text; the session's _navigate already turns thrown verb errors into its message.

**2026-11-08T22:37:50Z**

Done in this branch. The session creates EpubPager for every EpubDocument (EPUB and MOBI) in open, with initial: initialAddress, onPlace to acceptAddress(token) and onWarning to warn(token), then calls attachDocument(token, pager, contents) at once. contents is publication.contents, or one 'Chapter N' entry per linear spine item (reader.js rule: linear unless the attribute has a value other than yes), with hrefs relative to the package directory. EpubPager? get pager follows documentChanges. _clear disposes the pager. configure is gone from DocumentNavigator, EpubNavigator, PdfViewport and EpubPager (NavigatorPort keeps its own configure for the WebView). BookMap.chapterStep now takes the shown address: forward goes to the first chapter that starts after the page's end (location.end), else after its start. Design over ticket: the ticket says 'at or after its end'; the design's behavior test says the arrow skips a chapter that starts on the shown page, and a chapter whose first character is the page's last one is on the page, so the rule is strictly after the end. The session's invariants are now listed in its class comment; checkInvariants also checks that a pager exists exactly for an opened EPUB or MOBI document, that a navigator exists only with a document, and runs the pager's own checker. Proof: test/reader/session_native_test.dart opens every page start that epub.js saved in the three showcase books (epubjs-places.json, 20 and 23 px) through the session with the real pager, plus bookmarks at page starts, contents targets and search hits, and checks the shown page and every record the store receives. Interim until tc-1yif: the screen still builds the WebView viewport, whose attach replaces the pager as navigator. Because the pager is attached at open, reader.ready is true before the WebView loads: the 'Laying out the book' spinner no longer shows, and Contents, Search and bookmark taps before the WebView attaches go to the pager, which waits for a present that never comes, so they do nothing (no message, no data change). The book map comes from the publication's contents, not from reader.js's list. The pager never reports a place, because nothing presents to it. New ticket tc-klz2: Next chapter after opening at a saved place.
