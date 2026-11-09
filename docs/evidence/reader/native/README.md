# Native EPUB reader on Android and macOS (tc-1yif)

Date: 2026-11-08. The Android images come from a disposable emulator (AVD `bookfin-tc1yif`, Android 36, deleted after the check). The app signed in to the synthetic server `tool/showcase_fixture.dart` through `adb reverse`. The book is the fixture's First Frost EPUB.

| Image | What it shows |
| --- | --- |
| `01-open.png` | The book opens on the native page. The dock says "One. The Grafted Trees · Page 1 of 2". |
| `02-turned.png` | A swipe to the left turns to page 2 of 2. |
| `03-next-chapter-page.png` | A second swipe turns to the first page of chapter two. |
| `04-larger-text.png` | The text size is three steps larger. The page still starts at "Her grandmother kept a ledger". |
| `05-night.png` | The night theme. The page keeps its place. |
| `06-scrub-deck.png` | A slow drag on the scrub bar shows the deck of page cards. |
| `07-after-scrub.png` | The drag ends on the first page of chapter three. |
| `08-after-restart.png` | After a restart of the app, the book opens on the same page, at the same text size and theme, with its chapter title. |
| `09-dock-hidden.png` | A tap on the page hides the dock and the app bar. The page grows and keeps its place. |
| `macos-01-open-at-saved-place.png` | The macOS app (`tool/bookfin accept-macos`) opens First Frost at the place that an earlier run saved. |
| `macos-02-turned-with-arrow-key.png` | The right arrow key turns to the first page of chapter two. |

Images 01 to 07 come from the first build of the branch. Images 08 and 09 come from the second build, which adds the chapter title of a place that the book opened at. The two builds draw the steps of 01 to 07 the same way.
