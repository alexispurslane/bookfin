---
id: tc-pshi
status: open
deps: [tc-nang, tc-sqp7]
links: []
created: 2026-11-08T19:23:13Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-b2ey
---
# Check the native renderer against epub.js and keep epub.js places as fixtures

Goal: measure the product renderer against epub.js once more, and commit what epub.js wrote and measured, so that these tests outlive epub.js. This must merge before tc-rap6 deletes epub.js.

Design sections: "Places / Places that epub.js saved", "Testing / Fidelity check against epub.js".

Files: packages/flutter_epub_viewer/engine/trial/compare.cjs, test/reader/epub/trial/fidelity_test.dart, test/reader/epub/fidelity_test.dart (new), test/reader/epub/saved_places_test.dart (new), test/reader/epub/fixtures/ (new), docs/research/native-epub-fidelity.md (new).

Steps:
1. Extend compare.cjs to record, for each compared section at 20 and 23 pixels, the line starts and page starts (visible character indices) and each page start's saved location (cfi, quote, progress). For each book also record the hits of three fixed phrases (location and excerpt) and the location of each contents entry (resolveDestination).
2. Run it over the trial's sections and over the fixture books of tool/showcase_media.dart. Chromium must be at /Applications/Chromium.app or CHROME_BIN.
3. Commit test/reader/epub/fixtures/epubjs-places.json (fixture books). Commit test/reader/epub/fixtures/chromium-layout.json and epubjs-corpus-places.json for the downloaded books, keyed by the SHA-256 of each book file and the section index. These hold numbers and short strings only, never book files.
4. saved_places_test: every recorded place opens (placeOf, then the page that holds it) on a page whose first line holds the start of its quote. Where a native page and an epub.js page start on the same character, the native anchor JSON equals epub.js's. The fixture books run always. If files with the right SHA-256 are present, the downloaded books run on demand (BOOKFIN_EPUB_TRIAL=1).
5. fidelity_test: compares the native layout with chromium-layout.json on demand, without Chromium.

File rule: tc-4f3q runs at the same time and moves test/reader/epub/trial/support.dart and corpus_test.dart. Do not edit those two. Keep your changes in test/reader/epub/trial to fidelity_test.dart and book.dart.

## Design

docs/plans/native-epub-reader.md (epic boo-b2ey). Read the sections named in the description. The design decides the owners, interfaces and order. Ask the orchestrator before changing them.

## Acceptance Criteria

- Body text agrees on at least 99.9 percent of line starts and 98 percent of page starts at 20 pixels. The 23 pixel numbers are recorded.
- Every recorded epub.js place opens on the page that shows it (the trial had 661 of 661 and 706 of 706).
- docs/research/native-epub-fidelity.md records the numbers, the commands and the Chromium version.

