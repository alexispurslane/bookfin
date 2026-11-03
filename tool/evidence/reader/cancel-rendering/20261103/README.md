# Reader cancellation rendering exception

This is host regression evidence for `t0-ys9g`, dated November 3, 2026.
The starting commit is `ee2a2c1017079bf292cea285be6c6fc2f4faf7af`.
Its reader screen, PDF viewport, PDF addresses, and OCR coordinator match
production source `71af2886e722b7366d4d335622e55e18a151a3e0` exactly.
No device action or child agent ran in this task.

## Proven host failure

The complete reader screen reproduces the same error message as the retained
Android screenshot: `Null check operator used on a null value`.
Both `widget-red.txt` and all five cases in `coordinator-red.txt` identify the
throwing expression as `lib/reader/screen.dart:279:65` in the starting source:

```dart
                                    reader.visibleAddress!.page! /
                                    reader.visibleAddress!.pages!,
```

where

- `reader` is the active reading session.
- `visibleAddress` is the reading position that the viewport publishes.
- `page` is its source-page number, starting at 1.
- `pages` is its optional total page count.

Cancellation publishes the current address before page text finishes.
For a fresh scan, that address is `PdfAddress(1, 0)`, with no total page count.
Failed text extraction and unresolved saved text positions can also lack a total.
The screen checks only the page number before asserting that the total exists.
The exception replaces the reader controls with Flutter's error widget.
This is not a failure of the Android inspection helper.
The `_text!` expressions in the viewport do not throw in these reproductions.

The invariant for the screen is that a page fraction needs both a page number
and a total page count. A page number alone remains a valid reading position.
The existing screen now owns that distinction. It omits the progress indicator
when the total is absent, and displays the known page number without `of null`.
It does not change cancellation, recognition, addresses, or download ownership.
There is no exception handler, fabricated total, or text-position reset.

The host stack establishes the failure in the reproduced application path.
The Android screenshot has no stack. A new normal-app Android run must establish
device recovery and complete cancel/drain/retry and departure acceptance.

## Regression boundary

The first test uses the real `ReaderScreen`, `ReaderSession`, and `PdfViewport`
with held scan text. Earlier viewport-only tests omit the failing screen.
The five coordinator tests additionally use real `BundledEnglishText`, original
byte verification, cache files, and the session's download-read boundary.
The PDF raster completion and Android method channel are controlled host inputs.
These tests do not execute Tesseract on Android or prove native interruption.

The coordinator cases cover:

1. Cancellation before the original raster and recognition raster finish.
2. Cancellation while the native recognition result remains outstanding.
3. Retry success and ordinary recognition failure at both timing boundaries.
4. Retry waiting for an outstanding native call, without publishing its late text.
5. An unresolved page-two character-10 saved place and bookmark, preserved through
   cancellation and retry until an explicit source-page choice. That choice uses
   the selected recognition text without another native call.

All cases assert visible controls or original/reflow content, not only a status
flag. Existing native PDF and SQLite regressions also pass. They retain source
identity, nonzero saved addresses, cache reuse, selected text, and read ownership.

## Verification

All checks run through the pinned root Nix shell. The shell's dependency cache
was reused with `PUB_CACHE=/Users/alexispurslane/Development/bookfin/.cache/pub`.
No toolchain was installed globally.
Stored command output has trailing whitespace removed.

| Evidence | Command inside `nix develop --command bash -c` | Result |
| --- | --- | --- |
| `widget-red.txt` | `flutter test --no-pub test/reader/ocr_viewport_test.dart --plain-name "canceling unsettled scan text keeps the full reader controls usable" --reporter expanded` | Meaningful failure at the production null assertion |
| `coordinator-red.txt` | `flutter test --no-pub test/reader/ocr_cancel_screen_test.dart --reporter expanded` | Five meaningful failures at the same null assertion |
| `focused-green.txt` | `flutter test --no-pub test/reader/ocr_viewport_test.dart test/reader/ocr_cancel_screen_test.dart test/reader/ocr_position_test.dart test/reader/ocr_test.dart test/reader/ocr_read_lifetime_test.dart test/reader/pdf_navigation_test.dart test/reader/pdf_screen_test.dart --reporter expanded` | 43 passed |
| `full-checks.txt` | `bash tool/bookfin test` | Four shell checks passed; 489 Flutter tests passed, three gated tests skipped |
| `analysis.txt` | `flutter analyze --no-pub` and `dart format --output=none --set-exit-if-changed lib/reader/screen.dart test/reader/ocr_viewport_test.dart test/reader/ocr_cancel_screen_test.dart` | No analysis issues; no formatting changes |
| `final-checks.txt` | Both changed widget test files, followed by analysis and the same formatting check | Eight tests passed; no analysis issues or formatting changes |

The three skips require the journal measurement flag or separately running
Jellyfin plugin fixtures. They are not new skips. Host Flutter commands report
absent iOS SDKs before running. This does not fail the Android-targeted host tests.
No coverage, mutation testing, font correction, ticket closure, or Android
acceptance claim belongs to this change.

## Packaging handoff

After committing the correction and this evidence, build the normal ARM64 debug
APK through `bash tool/bookfin build-android` in the pinned shell. Keep build logs
outside the tracked source until export finishes. Export the clean commit with
`python3 tool/reader/native_package.py sources <new-output-directory>`.
Retain the APK, both package-verifier results, source manifest, and hashes in a
new worktree-local artifact directory. The existing combined artifact directory
in the main checkout stays read-only. The parent installs the candidate later.
