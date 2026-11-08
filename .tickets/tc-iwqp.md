---
id: tc-iwqp
status: open
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

