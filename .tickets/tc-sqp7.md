---
id: tc-sqp7
status: open
deps: [tc-bsen]
links: []
created: 2026-11-08T19:23:12Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-b2ey
---
# Find and write every saved place through the native DOM

Goal: one module that turns DOM positions into the places Bookfin saves, and back, with every rule that reader.js applies today.

Design sections: "Places" (all of it).

Files: lib/reader/epub/places.dart, packages/flutter_epub_viewer/lib/navigation.dart (ReadingLocation.end only), test/reader/epub/places_test.dart.

Interfaces (functions over DomSection and EpubPlace):

```dart
String spineStep(String opf, int index);
String cfiOf(String spine, DomSection dom, EpubPlace place);
EpubPlace? placeOf(DomSection dom, int section, String cfi);
EpubPlace wordStart(DomSection dom, EpubPlace place);
String quoteAt(DomSection dom, EpubPlace place);      // 120 characters
double progressAt(DomSection dom, EpubPlace place);   // 6 decimals
EpubPlace placeAt(DomSection dom, int section, double progress);
EpubPlace destination(DomSection dom, int section, String? fragment);
bool quoteMatches(DomSection dom, EpubPlace place, String quote);
String chapterTitle(DomSection dom, EpubPlace place,
    List<ContentsEntry> contents, String packagePath, String sectionPath);
/// The saved location of a page that starts at [start] and ends at [end].
ReadingLocation pageLocation(String spine, String sectionPath, DomSection dom,
    EpubPlace start, EpubPlace end, String chapter);
/// The location of a search hit that starts at [start].
ReadingLocation hitLocation(String spine, String sectionPath, DomSection dom,
    EpubPlace start, String chapter);
```

ReadingLocation gains `final double? end;`: the progress of the last visible character on the shown page. It is for display only. toJson does not write it and fromJson does not read it.

Rules: exactly those of packages/flutter_epub_viewer/engine/src/reader.js (visibleLocation, verifyLocation, resolveDestination, placeAt, quoteAt, progressAt) and of the trial's cfi.dart. A page's saved CFI is cfiOf(wordStart(start)). Its quote and progress are taken at that word start. A search hit's CFI is the match start itself.

## Design

docs/plans/native-epub-reader.md (epic boo-b2ey). Read the sections named in the description. The design decides the owners, interfaces and order. Ask the orchestrator before changing them.

## Acceptance Criteria

- One test per rule, with cases from reader.js behavior: a text node that starts with white space (wordStart), element ids as CFI assertions, a range resolves to its start, an offset past a node's end stops at its end, a quote across text nodes, progress without white space, placeAt at 0 and at 1, destination with a fragment, without one and to an element without text, and the chapter title from contents, from h1, from title and as 'Chapter N'.
- ReaderDocument.save of the EpubAddress for the trial's harbour passage page writes cfi epubcfi(/6/2!/4/26/1:0), as epub.js did.
- ReadingLocation.toJson output is unchanged. end is never saved.

