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

## Completed same-emulator measurements

The homepage shows one table of arithmetic mean times across three books:
*Pride and Prejudice*, *Moby-Dick*, and *Alice’s Adventures in Wonderland*.
For each engine and action, first average the measured elapsed times within
each book, then average those three book means. Each book has equal weight.
Round only the final result to one decimal millisecond. This is not an average
of medians or p90 values.

The [aggregate data](averages.json) records each book’s sample count, total
elapsed nanoseconds, mean, and the final equal-weight mean. Its source hash
identifies the unchanged [raw samples](../../../tool/research/epub_engines/evidence/results/samples.jsonl).
Only samples accepted by the existing benchmark validator enter the average.
There are 12 fresh opens and 36 samples of each other action per book and engine,
for 1,404 measured samples across 108 process runs. Equal sample counts mean
that pooling all three books gives the same arithmetic mean. The three warm
samples within a process are not independent process starts.

The original per-book median and p90 results remain in the
[full results](../../research/epub-engine-results.md), with the
[method](../../research/epub-engine-method.md),
[review](../../research/epub-engine-review.md), and
[summary JSON](../../../tool/research/epub_engines/evidence/results/summary.json).
No benchmark was rerun for this editorial change.

### Measurement scope

All three engines ran in small optimized release apps on the same Android 16
emulator on November 10, 2026. The emulator had four virtual ARM64 CPUs, 2 GiB
RAM, software graphics, and a 360 × 640 logical-pixel reading area. The measured
interval starts at the reading request and ends at a matching Android window
copy. It includes rendering, scheduling, content checks, and screenshot capture.
It is not pure engine CPU time, whole-app startup, or a physical Pixel measurement.

Fresh opens clear the test app’s book caches, but not Android’s file cache.
Cached reopens follow cache preparation. “Chapter turn (visited)” means turning
from the last page of one chapter into a chapter already visited in that run.
KOReader paginates the whole book during open and size changes. Bookfin can
finish pagination in the background; WebView lays out chapters as needed.
Page boundaries and illustration sizes differ.

Software graphics, Flutter texture composition, instrumentation, and changing
host load limit the comparison. The table does not establish an overall winner
or equal rendering quality. Historical desktop and headless-browser studies
are not included.

## Homepage organization and checks

The Reader chapter now contains the EPUB implementation, shared controls, and
one benchmark table. PDF reflow has its own chapter and before/after comparison.
The reflow picture follows the site theme: Cream at size 24 or Night at size 28,
both from the same page. Capture provenance remains linked next to the images.
History explains its shared audiobook and ebook actions beside the real capture.

The original hero, Why copy, Shelf, Player, installation instructions, and visual
style remain intact. Detailed benchmark qualifications belong in this note,
with the averaging rule and main limitations beside the homepage table.
[Verification](verification.json) records the numeric, markup, asset, and layout
checks for this revision. No application source or measurement evidence changed.
