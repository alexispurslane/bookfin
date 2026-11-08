---
id: tc-nh0b
status: open
deps: [tc-bsen]
links: []
created: 2026-11-08T19:23:12Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-b2ey
---
# Read each book's own style sheets, @import and embedded fonts

Goal: Standard Ebooks and other books get their own CSS, including sheets with @namespace, imported sheets and @font-face fonts. This absorbs te-9m1y without touching the sanitizer.

Design sections: "Coverage beyond the trial / Book style sheets" and "/ Embedded fonts".

Files: lib/reader/epub/css.dart, lib/reader/epub/prepare.dart, lib/reader/epub/fonts.dart (new), test/reader/epub/css_test.dart, prepare_test.dart, fonts_test.dart (new).

Interfaces:

```dart
// css.dart
class FontFaceRule {
  final String family; final String path; final int weight; final bool italic;
}
// StyleSheet.parse takes a callback that returns the CSS text of a
// publication path, or null, and follows @import to depth 4, never twice.
// MediaContext gains night: prefers-color-scheme: dark matches when night.

// prepare.dart
// SectionSource gains: final String fontPrefix;
//   ('bookfin-' + the first 12 hex digits of the publication identity)
// Its styleSheets map holds every sheet the section can reach.
// PreparedSection gains: final List<FontFaceRule> fonts; (faces its runs use)
// RunStyle.family is the one family to draw with:
//   '<fontPrefix>-<family>' for an embedded face, else 'Source Serif 4',
//   else 'monospace'.

// fonts.dart
class BookFonts {
  /// Registers each face once under its per-book family, from the bytes of
  /// its path. A face that fails to load is skipped.
  Future<void> load(Iterable<FontFaceRule> faces,
      Uint8List? Function(String path) bytes, String prefix);
}
/// The SFNT bytes of a TTF, OTF or WOFF 1 font, or null (WOFF 2 and
/// anything else). Pure Dart, safe in a worker.
Uint8List? sfntOf(Uint8List font);
```

Rules:
- url() and @import resolve only to publication paths (resolvePath). Anything else is ignored.
- Limits: 20,000 rules per sheet, 1,024 characters per selector, nesting depth 32. A sheet past a limit keeps the rules before it.
- Keep the trial's @namespace skipping and namespaced attribute selectors.
- The opsz and wght font variations that copy Chromium apply only to the reader font, never to an embedded face.
- Do not change packages/flutter_epub_viewer. The page source (tc-tjtc) passes Publication.bookStyles in through SectionSource.

## Design

docs/plans/native-epub-reader.md (epic boo-b2ey). Read the sections named in the description. The design decides the owners, interfaces and order. Ask the orchestrator before changing them.

## Acceptance Criteria

- A section linked to a Standard Ebooks core.css fixture (with @namespace epub) gets small caps headings and hanging verse indents as the sheet says.
- An @import of a sheet in the publication applies. A remote @import or a path outside the publication does nothing.
- prefers-color-scheme: dark rules apply only with night.
- sfntOf turns a WOFF 1 fixture into bytes that ui.loadFontFromList accepts, and returns null for WOFF 2.
- After BookFonts.load, a run in an embedded face lays out with that face's widths (measurably different from the reader font).
- prepareSections still runs inside Isolate.run.

