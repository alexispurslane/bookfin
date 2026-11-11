# EPUB section: implementation sources and measurement status

The homepage section describes the production EPUB reader, not the former
WebView reader or the early native-renderer trial. Sources were checked against
Bookfin commit `0f12f5eac34870f4b7d199fdc5509fa24690177b` on November 10, 2026.
This note supports ticket `boo-cldw`.

## What the implementation supports

| Homepage claim | Source and scope |
| --- | --- |
| EPUB layout and drawing run in Flutter. | [`layoutSection` in `layout.dart`](../../../lib/reader/epub/layout.dart#L3155) lays out prepared EPUB sections. [`drawPage` in `paint.dart`](../../../lib/reader/epub/paint.dart#L23) draws paragraphs, images, and decorations through `dart:ui`. [`screen.dart`](../../../lib/reader/screen.dart#L531) opens the production `EpubViewport`. |
| There is no WebView fallback for EPUB. | The production reader routes EPUB to [`EpubViewport`](../../../lib/reader/epub/viewport.dart#L38). The current [`pubspec.yaml`](../../../pubspec.yaml) has no WebView dependency. References to epub.js in the EPUB source document compatibility with old saved places or the former reader, not an active browser fallback. The older recommendation in `docs/research/native-epub.md` is superseded. |
| Size, Cream/Night, selection, and Copy belong to the shared reader. | [`EpubViewport`](../../../lib/reader/epub/viewport.dart#L38) receives size and Night settings. Its [`ReaderCopyArea`](../../../lib/reader/epub/viewport.dart#L148) handles selection and reports selected text. [`screen.dart`](../../../lib/reader/screen.dart#L531) connects these controls to the reading session and clipboard. |
| Links and footnotes work within the reader. | [`_followLink`](../../../lib/reader/screen.dart#L215) opens a recognized note in the reader's note sheet. Other links go to their destination in the book. This does not promise that every publisher's link or note is recognized. |
| Touch, keyboard, and trackpad turn pages. | [`EpubViewport`](../../../lib/reader/epub/viewport.dart#L133) handles page-turn keys and uses `PageSwipes`. [`page_swipes.dart`](../../../lib/reader/page_swipes.dart#L15) handles touch, trackpad pan, and horizontal scroll. |
| EPUB uses one shared Flutter implementation across platforms. | The [platform model](../../plans/platforms.md#the-platform-model) identifies Flutter EPUB drawing separately from platform-specific services. The same `lib/reader/epub/` implementation is used, rather than a separate EPUB engine for each platform. |

The portability claim applies to the EPUB reader, not to the whole app being
pure Dart or to every platform already having a released app. PDF, OCR, audio,
and storage have native dependencies or platform services.

The [platform survey](../../plans/platforms.md#survey-per-platform) records
Android as the primary target and a working macOS EPUB implementation. iOS,
Linux, and Windows app ports are not generally delivered. The homepage says
this beside the shared-implementation claim, not only in this note.

## Other rendering approaches

| Table row | Verified source | Meaning |
| --- | --- | --- |
| Android WebView | [Android Developers: Build web apps in WebView](https://developer.android.com/develop/ui/views/layout/webapps/webview) | WebView embeds web content in an Android app. It is not itself an EPUB package reader. A reader must supply the EPUB content as HTML and CSS. This row does not call headless desktop Chromium an Android WebView measurement. |
| KOReader | [KOReader's production `credocument.lua`, pinned to `c3e5f750b4e7a1b5afc5f6b62bdf6a004e28e518`](https://github.com/koreader/koreader/blob/c3e5f750b4e7a1b5afc5f6b62bdf6a004e28e518/frontend/document/credocument.lua#L71) | The document provider is `crengine`; line 104 loads `libs/libkoreader-cre`. Lines 1614–1616 register EPUB formats with this provider. Bookfin's [native EPUB research](../../research/native-epub.md#situation-check) also identifies it as the Cool Reader engine. No speed follows from its implementation language. |

These sources establish the rendering approaches. They do not establish a speed
ranking, identical features, or identical support for every EPUB stylesheet.

## Fresh comparable measurements are pending

The user requested new tests of Bookfin, Android WebView, and KOReader on the
same Android emulator, using minimal shell apps. The parent task owns those
tests. This homepage change performs no benchmark or device work. All three
timing cells remain `Results pending` until the parent provides verified data.

The final table and this note must name the common measured operation, time
unit, EPUB fixture, engine versions, emulator configuration, run count, and
cache state. They must distinguish work inside each shell from whole-app open
time and physical-device performance. Different measured operations must not
be combined into a speed multiplier.

Historical studies are deliberately excluded from the table:

- [`native-epub.md`](../../research/native-epub.md#speed) compares a Flutter-test
  host trial with epub.js in headless Chromium. Chapter layout, CPU preview
  drawing, browser first-show, and warm-preview times have different boundaries.
- [`epub-first-page-timing.md`](../../research/epub-first-page-timing.md) records
  Bookfin-specific investigations, not a matched three-engine comparison.
- [`epub-layout-cache.md`](../../research/epub-layout-cache.md) measures Bookfin
  cache behavior, not current end-to-end performance against other engines.

No historical host figure is represented as current Android performance. There
is no numerical result, winner, or inferred ranking in the prepared table.

## Homepage checks

The documentation-only check ran through `nix develop`. It found no unbalanced
tags, duplicate IDs, missing local paths, broken local evidence links, or
incorrect image dimensions. It checked all 12 homepage images and the table's
caption and header scopes. The PDF reflow, shared History, and reader sections
remain byte-for-byte unchanged. Existing external links and installation
commands also remain unchanged.

Actual T3 `html_preview` runs used the homepage's current CSS and its header,
contents, and new EPUB section. Both bundled fonts were embedded as data URIs
and reported loaded before layout measurements. No external font, library, or
server was used. The preview HTML is stored in ignored scratch at
`.cache/boo-cldw/epub-preview.html`; an SVG metadata carrier lets T3 inline that
complete HTML without changing the page under test. This is a homepage layout
check, not an app screenshot or a performance measurement.

| Preview | Page width | Table region | Table content | Outcome |
| --- | --- | --- | --- | --- |
| Cream, phone | 390 px | 350 px | 672 px | No page overflow; the table scrolls within its region. |
| Cream, desktop | 1280 px | 1180 px | 1180 px | No page overflow; all columns fit. |
| Night, phone | 390 px | 350 px | 672 px | No page overflow; the region accepted keyboard focus and scrolled 322 px. |

The parent owns the final full-page visual review and the new benchmark
results. This leaf ran no Flutter suite, app build, benchmark, or device action.
