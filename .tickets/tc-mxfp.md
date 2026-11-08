---
id: tc-mxfp
status: open
deps: [tc-sqp7, tc-866u, tc-tjtc]
links: []
created: 2026-11-08T19:23:12Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-b2ey
---
# Move through the native EPUB with a pager that owns the shown place

Goal: EpubPager implements DocumentNavigator for EPUB and MOBI. It owns the shown place and the shown page, carries out the session's navigation, reports places, draws scrub deck pages and runs searches.

Design sections: "Navigation", "Pages" (rules 3 to 6), "Places / Data safety", "The viewport" (the pager's side), "State and owners".

Files: lib/reader/epub/pager.dart (new), test/reader/epub/pager_test.dart.

Interfaces:

```dart
class ShownPage { final LaidPage page; final ui.Picture picture; }

class EpubPager implements DocumentNavigator {
  EpubPager(EpubDocument document,
      {ReaderAddress? initial,
      required ValueChanged<EpubAddress> onPlace,
      required ValueChanged<String> onWarning,
      PageSource? source});
  ValueListenable<ShownPage?> get shown;
  /// Keeps the shown place. Notifies later, never during the call.
  void present(PageSettings settings);
  /// The href (relative to the package document) of the link under [point].
  String? linkAt(Offset point);
  // DocumentNavigator: move, display, contents, seek, preview, search,
  // cancelSearch. configure exists only until tc-zevb removes it from the
  // interface; it does nothing.
  void dispose();
  void checkInvariants(); // on demand, every build
}
```

Rules:
- Open: if initial resolves (placeOf) and its quote matches, the shown place is its place. Show its page and report the initial address object itself, unchanged. If initial does not match, show the book's start, call onWarning('The saved place does not match this text. Reading starts at the beginning.') and report nothing until a move. With no initial address, show the start and report its page.
- move: the page after or before the shown page (design rules 4 to 6), then report its pageLocation. At the book's ends do nothing.
- display: resolve and match the quote. On failure throw, so the session shows its message. Else show the page and report.
- contents: resolve the href against the package document's directory to a spine section and a fragment, then destination(). Unknown targets throw.
- seek: placeAt, then the page, then report.
- preview: the true page of placeAt(part, progress) (anchored false, urgent during a drag, abandon honored). picture() at width, Picture.toImage, then PagePreview with start = the start progress, end = the progress of the last visible character, previous = the start of the true page before (or the previous section's last page start), next = the next page's start (or the next section's start). Each neighbor place must be held by exactly one page (PagePreview.holds).
- present: re-anchor at the shown place. Report nothing.
- search: batches of about 8 sections through searchSections (tc-866u) in Isolate.run. Stop between batches after cancelSearch(request).
- linkAt: hit test the shown page, take the nearest a[href] ancestor, resolve it against the section path, return it relative to the package directory.
- Report a place only after its page is on shown.
- Invariants: the shown page belongs to the current settings, holds the shown place or starts at its line, and is pinned in the page source.

## Design

docs/plans/native-epub-reader.md (epic boo-b2ey). Read the sections named in the description. The design decides the owners, interfaces and order. Ask the orchestrator before changing them.

## Acceptance Criteria

- Turns forward and back within a section, across sections, and at both ends of the book.
- Opening at a saved place shows a page whose first line holds it and reports the identical address object.
- present with a new text size keeps the shown place and reports nothing. Over the fixture books, the text shown over successive turns after that covers each section in order, with no text skipped.
- A saved place with a wrong quote opens at the start with the warning and reports nothing until a move.
- seek lands on the page that holds placeAt. contents and links land on their destination. display of a search hit lands on its match.
- preview returns the true page, and each previous and next place is held by exactly one page. A deck page draws in under 20 ms on the host and under 0.3 s on the Android emulator (the goal of t6-rt20).
- search returns E6's hits in book order and stops between batches after a cancel.
- checkInvariants passes after every step of these tests.


## Notes

**2026-11-08T20:42:59Z**

From tc-sqp7: destination(dom, section, fragment) returns null when the fragment names no element (reader.js throws there). The pager must handle the null and show its error, as today. pageLocation needs the page's last visible place as end: use LaidPage.endPlace from tc-nang.

**2026-11-08T21:29:52Z**

From tc-866u (orchestrator accepts): SearchSection.xhtml is bytes (decoded in the worker); use spineSteps(opf) once per book, not spineStep per section; searchBook(sections, query, contents, packagePath, isCurrent:) keeps reader.js's limits and errors, and the pager owns the request and its cancel.
