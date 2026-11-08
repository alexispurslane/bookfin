---
id: tc-nang
status: closed
deps: [tc-bsen]
links: []
created: 2026-11-08T19:23:12Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-b2ey
---
# Lay out a section in resumable runs that start at any page start

Goal: replace the trial's one-shot section layout with layout runs that work in time-boxed steps and can start at any page start.

Design sections: "Pages" (the property and rules 1 to 6), "Layout off the frame path / Steps".

Files: lib/reader/epub/layout.dart, lib/reader/epub/paint.dart, test/reader/epub/layout_run_test.dart (new).

Interfaces (the renderer track and the page source rely on these signatures; keep them stable after this ticket):

```dart
/// Where a page begins: line [line] of flow item [item].
class PageStart { const PageStart(this.item, this.line); final int item; final int line; }

/// One cut page. It never changes once a run publishes it.
class LaidPage {
  int get section; PageSettings get settings; PageStart get start;
  EpubPlace? get startPlace; // first text, else first image, else null
  EpubPlace? get endPlace;   // last visible character on the page
  int get startVisible;      // visible characters of the section before it
  int get endVisible;        // visible characters through its last one
  bool get last;             // the section's last page
  void dispose();            // its paragraphs
}

class LayoutRun {
  /// A run of [section] from [from], or from the section start.
  LayoutRun(PreparedSection section, {PageStart? from});
  /// Lays out paragraphs until [budget] is spent or [want] pages are cut
  /// (null: to the end). A step ends after the paragraph that crosses the
  /// budget.
  void step(Duration budget, {int? want});
  List<LaidPage> get pages;
  bool get done;
  void dispose();
}

/// The page start of the line that holds [place].
PageStart lineStart(PreparedSection section, EpubPlace place);

// paint.dart
ui.Picture drawPage(LaidPage page, PageImages images);
```

Rules:
- Apply break-inside: avoid and break-after: avoid as each strip slice is added. The result equals the trial's.
- A run that starts inside a paragraph lays out the whole paragraph and keeps the lines from its start line, so orphans and widows see the whole paragraph.
- A run publishes a page at one of two moments: its strip slices reach one page height below the page's start, or it reaches the section end.
- layoutSection becomes a main run stepped to the end. If no test needs it, delete it.
- A page owns its paragraphs. The page source (tc-tjtc) decides how long pages live.

## Design

docs/plans/native-epub-reader.md (epic boo-b2ey). Read the sections named in the description. The design decides the owners, interfaces and order. Ask the orchestrator before changing them.

## Acceptance Criteria

- Over the fixture books and long helper prose: for every true page start, a run from it cuts the same following pages (start, end, line starts) as the main run.
- A run stopped after every step and resumed gives the same pages as a run with an unlimited budget.
- With a counted budget, a step lays out at most one paragraph after the budget is spent.
- A page that starts inside a paragraph keeps the orphans and widows rules as in the main run.
- lineStart(place) returns a page start whose first line holds place.
- Published pages never change.
- The existing layout tests pass.


## Notes

**2026-11-08T19:47:15Z**

From tc-bsen: layout.dart walks PreparedSection.flow with a stack of open blocks (_OpenBlock: placement, boxTop, firstSlice) and carries margin state (_positive, _negative), _avoidNext and a pending list marker between items. A run that starts at a page start must rebuild that stack from the BlockStart and BlockEnd items before its start item. A shrink-to-fit block measures its paragraphs (_maxContent) to place itself. An empty block is detected as a BlockStart followed at once by its BlockEnd.

**2026-11-08T20:19:39Z**

Interfaces as built: LayoutRun also takes an optional clock (Duration Function()) for counted budgets in tests, and exposes reached (the next flow item) and checkInvariants(). LaidPage also exposes top, bottom, height, slices, decorations, pieces and lineStarts for drawing and tests. Pages share a split paragraph through a holder count on Piece, so each page disposes on its own. decodeImages now takes Iterable<LaidPage>. layoutSection stays as the main run stepped to the end, because tests and the trial tools use ChapterLayout. A page with no place takes startVisible from the previous page of its run (the trial took the next page's); no trial page differs.
