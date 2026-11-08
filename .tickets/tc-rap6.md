---
id: tc-rap6
status: open
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

