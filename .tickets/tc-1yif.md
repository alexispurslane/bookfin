---
id: tc-1yif
status: open
deps: [tc-1iap, tc-zevb]
links: []
created: 2026-11-08T19:23:12Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-b2ey
---
# Make the native viewport the EPUB and MOBI reader on every platform

Goal: the reader screen shows EpubViewport for every EPUB and MOBI book on Android, macOS, Linux, Windows and iOS.

Design sections: "The viewport", "Navigation".

Files: lib/reader/screen.dart, test/reader/screen_test.dart, dock_test.dart, appearance_test.dart, shared_appearance_test.dart, docs/plans/platforms.md.

Changes:
- _viewport builds EpubViewport(pager: reader.pager!, fontSize: the text scaler applied to reader.fontSize, night, onTap: toggle the controls, onTurn: reader.move, onLink: reader.goToContents, onCopy: write the text to the clipboard).
- Remove the epubViewportSupported gate, its 'EPUB reading is available in the Android app' message, and the 'Laying out the book' spinner. A native book is ready at once. The PDF path stays.
- Rewrite the WebView fakes (InAppWebViewPlatform) in dock_test, appearance_test and shared_appearance_test against the native viewport: a tap hides and shows the dock, and text size and theme reach the page.
- platforms.md: the Reading seam row and each platform's EPUB and MOBI rows. EPUB renders in Flutter everywhere. MOBI needs libmobi in the runner.

## Design

docs/plans/native-epub-reader.md (epic boo-b2ey). Read the sections named in the description. The design decides the owners, interfaces and order. Ask the orchestrator before changing them.

## Acceptance Criteria

- Widget tests show the native page for an EPUB on the android, macos, linux, windows and ios target platforms.
- A tap hides and shows the dock. A swipe turns. A link jumps. Text size and theme changes keep the place.
- Device check on your own Android emulator, never a shared one and never with flutter drive (it uninstalls the app). Use the T3 device tools (device_list, device_open, the device-bound agent-device command). Open a fixture EPUB, turn pages, change the text size, switch the theme, scrub with the deck, restart the app and land on the same page. Keep the screenshots under docs/evidence/reader/native/.
- The macOS app (tool/bookfin build-macos) opens a fixture EPUB and turns pages.

