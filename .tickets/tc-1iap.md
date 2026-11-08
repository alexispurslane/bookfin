---
id: tc-1iap
status: open
deps: [tc-mxfp]
links: []
created: 2026-11-08T19:23:12Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-b2ey
---
# Show the pager's pages in a native viewport with turns, taps, links and keys

Goal: EpubViewport, the leaf widget that draws the pager's shown page and reports what the person did. It causes no side effect except present, which is a request for pages.

Design section: "The viewport".

Files: lib/reader/epub/viewport.dart (new), test/reader/epub/viewport_test.dart.

Interface:

```dart
class EpubViewport extends StatefulWidget {
  const EpubViewport({super.key, required this.pager, required this.fontSize,
      required this.night, required this.onTap, required this.onTurn,
      required this.onLink, required this.onCopy});
  final EpubPager pager;
  final double fontSize; // after the system text scale
  final bool night;
  final VoidCallback onTap;            // a tap on no link, with no selection
  final ValueChanged<bool> onTurn;     // true: next page
  final ValueChanged<String> onLink;   // href for DocumentNavigator.contents
  final ValueChanged<String> onCopy;   // used by tc-iwqp
}
```

Rules:
- Present PageSettings(width, height, fontSize, night) from the viewport's own layout whenever the size, the text size or the theme changes. Never notify during build.
- A render object paints shown.picture at logical size. Before the first page it paints the theme's paper. It keeps the last picture until a new one arrives.
- Tap: linkAt(point) non-null calls onLink, else onTap.
- Swipe: a horizontal drag over 60 logical pixels with under 50 vertical calls onTurn (left: true).
- Keys (with focus): right arrow, Page Down and Space call onTurn(true). Left arrow and Page Up call onTurn(false). A horizontal trackpad scroll of 80 logical pixels calls onTurn.
- The scrub deck keeps the viewport as its page child. The deck's opening must not rebuild it.

## Design

docs/plans/native-epub-reader.md (epic boo-b2ey). Read the sections named in the description. The design decides the owners, interfaces and order. Ask the orchestrator before changing them.

## Acceptance Criteria

Widget tests with a real pager on the fixture books:
- The painted page equals the pager's shown picture.
- A tap away from links calls onTap. A tap on a link calls onLink with its href and not onTap.
- A swipe left calls onTurn(true), right onTurn(false). A short or diagonal drag calls nothing.
- The keys call onTurn as listed.
- A resize presents new settings and the shown place stays.
- A text size or theme change presents new settings, and the old page stays painted until the new one arrives.


## Notes

**2026-11-08T22:04:24Z**

From tc-mxfp: present() throws ArgumentError unless the width, height and text size are finite and above 0, so present only after layout gives a size. linkAt(point) takes logical pixels from the page's top left corner and returns null outside text of a link. shown notifies twice for a page with images: the draft first, then the picture with decoded images.
