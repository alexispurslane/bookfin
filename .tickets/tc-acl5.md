---
id: tc-acl5
status: in_progress
deps: []
links: []
created: 2026-11-08T19:23:12Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-b2ey
---
# Keep book style sheets, image sizes and contents beside the pinned publication identity

Goal: give the native renderer what it needs from the archive without changing one admitted byte, so that every saved place keeps matching its book.

Design sections: "Places / The saved form stays", "Coverage beyond the trial / Book style sheets".

Why: ReaderDocument.restore compares the publication identity, a hash of every admitted file. Any change to admission output orphans every saved place of the books it touches. So admission output stays byte for byte, and new data goes beside it.

Files: packages/flutter_epub_viewer/lib/publication.dart, test/reader/epub/admission_test.dart (new).

Interfaces (new fields of Publication, all outside the identity):

```dart
/// The original text of each style sheet in the manifest, by path, as the
/// book wrote it.
final Map<String, String> bookStyles;

/// The pixel width and height of each admitted PNG and JPEG, by path, from
/// the raster check that admission already runs.
final Map<String, (int, int)> imageSizes;

/// The contents: the EPUB 3 navigation document's toc, else the NCX navMap,
/// else empty. Each href is relative to the package document's directory
/// (the convention that BookMap.of resolves) and points into the spine.
final List<ContentsEntry> contents;
```

Rules:
- The admitted files, the identity input and Publication.policy stay byte for byte. Add nothing to resources or to the identity hash.
- bookStyles: decode as UTF-8, else Latin-1. At most maxResourceBytes per sheet. Only text/css items that admission kept in its types.
- contents: parse the raw navigation document before _clean unwraps nav, with the same guards as _xml. Use the nav whose epub:type contains toc. Title: trimmed text of the a or span, else 'Untitled chapter'. Depth: nesting, at most 16. Drop an entry whose target is not a spine document. Without a nav document, use the NCX navMap (navPoint, navLabel, content src).
- ContentsEntry is the class in navigation.dart. The 'Chapter N' fallback for an empty list stays with the session (tc-zevb).

## Design

docs/plans/native-epub-reader.md (epic boo-b2ey). Read the sections named in the description. The design decides the owners, interfaces and order. Ask the orchestrator before changing them.

## Acceptance Criteria

- A test pins the identity of each fixture book from tool/showcase_media.dart and of the EPUB fixtures under test/reader/fixtures. The golden values are computed before the change. If admission output changes by one byte, the test fails.
- A Standard Ebooks shaped fixture whose sheet starts with '@namespace epub "http://www.idpf.org/2007/ops";' keeps its full text in bookStyles. Its admitted CSS stays as today.
- contents lists an EPUB 3 fixture's toc from its nav, with depths, and an EPUB 2 fixture's from its NCX.
- BookMap.of with these entries puts each chapter start at its target element (book_map_test style).
- imageSizes has the size of every admitted PNG and JPEG.
- Existing publication tests pass unchanged.


## Notes

**2026-11-08T19:39:06Z**

Implemented. Three departures from the ticket text: (1) test/reader/fixtures has no EPUBs, so the identity test pins the committed EPUBs in tool/research/readers/fixtures and tool/evidence/reader/android-remaining instead, beside the three showcase books (zipped again with a fixed file time) and the seven trial books when .cache/epub-trial/books exists. (2) No Latin-1 fallback for bookStyles: admission already refuses a sheet that is not UTF-8, so the fallback could never run, and admitting such books would change admission behavior. (3) Contents titles also collapse inner white space to one space, besides the trim. A nav toc that yields no entries falls back to the NCX.
