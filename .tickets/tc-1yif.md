---
id: tc-1yif
status: in_progress
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


## Notes

**2026-11-08T22:09:07Z**

From t1-5r2c: for a native EPUB page, take the dock's place label from pager.pageNumber (a ValueListenable), not from ReaderAddress.page and pages, which the native reader leaves null: 'Page N' while count is null, 'Page N of M' once count is set (user decision 2026-11-08, option a). Subscribe at the label with a ValueListenableBuilder.

**2026-11-09T00:54:10Z**

Done in this branch. The screen builds EpubViewport(pager: reader.pager, fontSize: text scaler applied to reader.fontSize, night, onTap toggles the controls, onTurn: reader.move, onLink: reader.goToContents, onCopy: Clipboard.setData) for every EPUB and MOBI on every platform. Removed: the epubViewportSupported gate and its Android-only message, and the 'Laying out the book' spinner. The 'Checking the downloaded EPUB' spinner and 'This EPUB is not open' now key on reader.pager instead of reader.publication. The WebView code and epub.js stay for tc-rap6. Dock label: for a native page, a ValueListenableBuilder on pager.pageNumber shows 'Page N', then 'Page N of M'; while the number is null it shows the book share ('37%'), as before, or 'Page progress unavailable' without a map. Found on the device and fixed here: a saved place has no chapter title (toJson leaves it out), so after opening at a saved place the dock said 'Current chapter unavailable'; the label now falls back to the book map's chapter at the place, the rule the dragged label already used. The 'Page N' state (count still unknown) could not be observed in a widget test: under the test clock one pump runs every layout step of a chapter. Tests: screen_test (native page on android, iOS, macOS, linux, windows; swipe both ways; link tap), dock_test (tap hides and shows the dock on the same page; Page 1 of M, Page 2 of M; chapter named after opening at a saved place), appearance_test and shared_appearance_test rewritten against the pager. Device: own AVD bookfin-tc1yif (deleted), synthetic server through adb reverse; screenshots in docs/evidence/reader/native/. macOS: accept-macos with a new EPUB step opened First Frost at its saved place and turned with the right arrow key (macos-*.png); the run then failed at its sync step, which t7-5zw9 records. New tickets: t7-hufl, t7-5zw9.
