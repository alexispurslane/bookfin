---
id: tc-iwqp
status: in_progress
deps: [tc-fz4n]
links: []
created: 2026-11-08T19:23:13Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-b2ey
---
# Select and copy text on a native page

Goal: the person selects text on the shown page and copies it, as the WebView allowed.

Design section: "The viewport" (selection and copy).

Files: lib/reader/epub/viewport.dart, lib/reader/epub/selection.dart (new), test/reader/epub/selection_test.dart.

Rules:
- A Selectable render object for the page, in Flutter's SelectionArea framework. A long press selects the word under the finger (ui.Paragraph.getWordBoundary). Handles extend the selection across the paragraphs of the page. Selection rectangles come from getBoxesForRange.
- The selected text is the DOM text of the selection, without soft hyphens.
- The context menu offers Copy, which calls onCopy. The screen already writes the clipboard (tc-1yif).
- A page turn clears the selection. While text is selected, a tap clears it and does not call onTap, and a swipe does not turn (reader.js behavior).
- Desktop: a mouse drag selects, Ctrl or Cmd plus C copies, Ctrl or Cmd plus A selects the page.

## Design

docs/plans/native-epub-reader.md (epic boo-b2ey). Read the sections named in the description. The design decides the owners, interfaces and order. Ask the orchestrator before changing them.

## Acceptance Criteria

- A long press selects the word. Dragging a handle extends the selection across paragraphs. Copy calls onCopy with the text.
- A tap with a selection clears it and does not call onTap. A swipe with a selection does not turn.
- A page turn clears the selection.
- On desktop, a mouse drag and the copy shortcut report the same text.


## Notes

**2026-11-09T02:13:20Z**

Done in this branch. lib/reader/epub/selection.dart: PageSelection, the one Selectable of a SelectionArea in the viewport, owned by the page's render object. Carets are (text line of the page, code unit). Long press selects a word (getWordBoundary), handles and mouse drags move one edge, select all takes the page, and a new page (not the same page with decoded images) clears it. Rectangles come from getBoxesForRange at each line's exact place. The copied text comes from bookUnits in semantics.dart, which the semantics also use, so inserted hyphens, soft hyphens and word joiners never appear; white space copies as one space, br as a line break, and each paragraph or cell starts a new line. Menu: Copy (onCopy; on Android it ends the selection) and Select all. Cmd or Ctrl+C reports through onCopy by overriding CopySelectionTextIntent. A tap with a selection clears it and does not call onTap; a tap on a link still follows it (design doc). The swipe now watches the pointer itself, as reader.js did, because the selection region claims horizontal touch drags; a swipe with a selection does not turn. The viewport shares one focus node with the selection region; its keys turn pages first. The viewport now needs an Overlay and Material localizations, as every screen gives it; the test harness gained onScreen(). Device: own AVD bookfin-tciwqp (deleted), evidence in docs/evidence/reader/native/selection/. macOS not checked by hand (no mouse tool; accept-macos deletes the sign-in); desktop widget tests cover it. New tickets: tf-e4nk (double-click selects a word), tf-1rv4 (search field paste of a line break).
