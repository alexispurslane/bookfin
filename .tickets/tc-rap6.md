---
id: tc-rap6
status: closed
deps: [tc-1yif, tc-fz4n, tc-iwqp, tc-pshi, tc-4f3q]
links: []
created: 2026-11-08T19:23:13Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-b2ey
---
# Remove the WebView reader, epub.js and their tests

Goal: delete the WebView reader and everything that only it used, once the native reader is the only reader and epub.js's results are committed.

Design section: "Removal".

Files and changes:
- Delete packages/flutter_epub_viewer/: the WebView viewport, resources.dart, navigation.dart, the epub.js and reader.js assets, the engine sources and license files, engine/test/*.cjs and engine/trial/compare.cjs.
- Move publication.dart to lib/reader/epub/publication.dart unchanged. Move ReadingLocation, ContentsEntry, SearchHit and SearchReport into lib/reader/document.dart unchanged. Update every import in lib/, test/ and tool/reader/.
- pubspec.yaml and pubspec.lock: drop flutter_epub_viewer and flutter_inappwebview.
- lib/reader/document.dart: delete EpubNavigator and the PagePicture decoding.
- lib/reader/session.dart: delete attach (the NavigatorPort adapter) and the export of navigation.dart.
- lib/main.dart: delete the epub.js license line.
- Tests: delete the ReaderResources tests in test/reader/publication_test.dart and test/reader/page_preview_sources_test.dart. Replace the NavigatorPort fakes in test/reader/screen_test.dart and session_test.dart with DocumentNavigator fakes and attachDocument.
- Delete test/reader/epub/trial/ (the plan step for Chromium). Keep fidelity_test.dart, saved_places_test.dart and their fixtures.
- flake.nix: if nothing else uses nodejs_22, drop it.
- docs/reader-implementation.md and docs/plans/platforms.md: remove the WebView text.

After this merges, the orchestrator can close tf-z3wm, tf-4fv5, tf-gnuk and t6-rt20 (see the design's table of obsolete tickets).

## Design

docs/plans/native-epub-reader.md (epic boo-b2ey). Read the sections named in the description. The design decides the owners, interfaces and order. Ask the orchestrator before changing them.

## Acceptance Criteria

- grep finds no flutter_inappwebview, flutter_epub_viewer, epub.js or reader.js in lib/, test/, tool/reader/, pubspec.yaml or flake.nix.
- The identity test from tc-acl5 passes after the move, with identities unchanged.
- saved_places_test and the full test suite pass. flutter analyze is clean.
- The Android APK and the macOS app build and open a fixture EPUB.


## Notes

**2026-11-08T21:57:18Z**

tc-4f3q moved test/reader/epub/trial/book.dart (TrialBook, now CorpusBook, which reads Publication.bookStyles and imageSizes as PageSource does) and support.dart into test/reader/epub/corpus/, and replaced trial/corpus_test.dart and benchmark.dart with test/reader/epub/corpus_test.dart. saved_places_test.dart now imports corpus/book.dart, so deleting test/reader/epub/trial/ leaves it intact. trial/ holds only fidelity_test.dart (the Chromium tooling).

**2026-11-09T06:39:37Z**

Deleted packages/flutter_epub_viewer/ (WebView viewport, resources.dart, navigation.dart, epub.js and reader.js assets, engine sources, engine tests, compare.cjs, licenses), test/reader/epub/trial/, EpubNavigator, ReaderSession.attach, the epub.js license entry, the ReaderResources tests and the EPUB PagePicture preview test. Moved publication.dart to lib/reader/epub/publication.dart (only its import of navigation.dart changed, to ../document.dart). Moved ReadingLocation, ContentsEntry, SearchHit and SearchReport into lib/reader/document.dart unchanged. Test fakes ControlNavigator (was ControlPort) and DeferredSearch now implement DocumentNavigator. pubspec drops flutter_epub_viewer and flutter_inappwebview; the lock loses 10 packages; macOS plugin registration loses InAppWebViewFlutterPlugin. Acceptance differences: grep still finds epub.js and reader.js in lib/ and test/ comments that name where the saved CFI dialect and the kept fixtures came from, as the design keeps those records; flake.nix still lists nodejs_22 (td-yglw); the macOS build and a device open were outside this run. Rewrote docs/reader-implementation.md for the native reader; platforms.md was already current; README's macOS paragraph now says EPUB opens. Tests 1874 -> 1868: the 3 env-gated trial tests and 3 WebView-only tests went away.
