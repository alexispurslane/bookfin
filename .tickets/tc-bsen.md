---
id: tc-bsen
status: closed
deps: []
links: []
created: 2026-11-08T19:23:12Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-b2ey
---
# Promote the trial renderer into lib/reader/epub and split prepare from layout

Goal: make the boo-ju83 trial code the product module, in the file layout of the design ("Modules"). Split the work that needs no dart:ui (parse, cascade, box building, white space collapsing, styled runs) from the work that needs it (paragraphs, block flow, page cuts), so that a worker isolate can run the first part. Behavior stays as the trial measured it.

Design sections: "What stays the same", "Terms", "Modules".

Files:
- New, moved from lib/reader/native_epub/ with git mv where possible: lib/reader/epub/dom.dart, css.dart, places.dart (from cfi.dart), prepare.dart, layout.dart, paint.dart.
- New tests: test/reader/epub/helpers.dart, css_test.dart, places_test.dart (from cfi_test.dart), layout_test.dart, prepare_test.dart.
- Tool code moved to test/reader/epub/trial/: book.dart (TrialBook), support.dart, benchmark.dart, corpus_test.dart, fidelity_test.dart. Mark each as tool code at its top.
- Delete: lib/reader/native_epub/, test/reader/native_epub/, tool/epub_trial/.

Interfaces:

```dart
// dom.dart
/// A place in an EPUB: a section, a node's document order in it, and a
/// code unit offset in a text node (0 for an element).
class EpubPlace implements Comparable<EpubPlace> {
  const EpubPlace(this.section, this.node, this.offset);
  final int section; // spine index
  final int node;    // DomNode.order
  final int offset;
}

// prepare.dart (calls nothing in dart:ui)
class PageSettings {
  const PageSettings({required this.width, required this.height,
      required this.fontSize, required this.night}); // == and hashCode
}
class SectionSource {
  final int index; final String path; final String xhtml;
  final Map<String, String> styleSheets;          // path -> CSS text
  final Map<String, (int, int)> imageSizes;       // path -> pixels
}
class PreparedSection {
  final int index; final PageSettings settings; final DomSection dom;
  final List<FlowItem> flow; final List<RunStyle> styles;
}
List<PreparedSection> prepareSections(
    List<SectionSource> sources, PageSettings settings);
```

FlowItem is a sealed class: BlockStart (box metrics resolved to pixels), BlockEnd, ParagraphItem (styled runs, placeholders, the text map data, the first-line indent), ImageItem, RuleItem. RunStyle holds plain values (family list, size, weight, italic, spacing, line height, decorations, small caps, old-style figures, vertical align). layout.dart turns each RunStyle into a ui.TextStyle once. layout.dart keeps the trial's whole-section entry for now (layoutSection over a PreparedSection). tc-nang replaces it with resumable runs.

Notes:
- PageSettings replaces the trial's PageTheme. The font family (Source Serif 4), the line height (1.65) and the reader's added rules become constants.
- Remove PageTheme's pageBreaks and syntheticBold options. The product always uses the WebView look: page breaks ignored, bold drawn as the thickened regular face. Remove the forced-break code and its test.
- Image sizes come in through SectionSource. Tests compute them from fixture bytes with the image package's header decoder. prepare must not use ui.ImageDescriptor.
- The support check stays only as corpus tooling under test/reader/epub/trial/. Nothing in lib/ uses it.
- test/reader/epub/helpers.dart belongs to this ticket. Later tickets put new helpers in their own test files.
- Do not change packages/flutter_epub_viewer.

## Design

docs/plans/native-epub-reader.md (epic boo-b2ey). Read the sections named in the description. The design decides the owners, interfaces and order. Ask the orchestrator before changing them.

## Acceptance Criteria

- Every trial test that still applies passes from its new place with the same expectations. Only the page-break option test goes.
- A test runs prepareSections inside Isolate.run and lays out the result on the UI isolate. The pages equal those of a section prepared on the UI isolate.
- No app code imports lib/reader/epub/ yet. flutter analyze is clean.
- lib/reader/native_epub/, test/reader/native_epub/ and tool/epub_trial/ are gone.
- When the books are present, the on-demand trial corpus run (BOOKFIN_EPUB_TRIAL=1) still works from test/reader/epub/trial/.


## Notes

**2026-11-08T19:47:15Z**

Done in lib/reader/epub/{dom,css,places,prepare,layout,paint}.dart. Deviations from the ticket text: (1) EpubPlace replaced the trial's DomPosition everywhere, so places.dart already has tc-sqp7's signatures for cfiOf, placeOf, wordStart, quoteAt and progressAt. (2) No RuleItem: the trial draws a rule as an empty bordered block, so a rule is a BlockStart followed at once by its BlockEnd. (3) RunStyle has no vertical align: prepare turns it into RaisedRun.shift in pixels. RunStyle.family is the one resolved family, as tc-nh0b expects. (4) Lengths that depend on a paragraph's own width (text-indent, inline image sizes) stay as Length or ImageSizing and resolve in layout, because a shrink-to-fit box gets its width only from measured paragraphs. Equivalence: all 317 sections of the 10 trial books at 20 and 23 px gave identical pages, slices, places, pieces and decorations to the HEAD trial code; the corpus support and CFI round-trip results equal the trial's results byte for byte.
