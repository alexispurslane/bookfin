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

The corrected source commit is `d8e1021fef2be69291d135594a45d556570c235f`.
The working tree was clean before source export and after build and verification.
The later packaging-evidence commit does not change application source.

The artifact directory is
`/Users/alexispurslane/.t3/worktrees/bookfin/t3-f29350e1/.cache/artifacts/bookfin-d8e1021-cancel`.
It contains the normal `bookfin-d8e1021-arm64-debug.apk`, the matching source
bundle under `source/`, full command output, and both empty clean-status files.
`artifact.json` records the absolute paths and verification results.

| Artifact | SHA-256 |
| --- | --- |
| Normal ARM64 debug APK | `8b31c7448f746226453d4677f944c9ba4f5668f657bba8015f94973372744e09` |
| `source/bookfin-source.tar` | `3dd0c18fb2cdc3b94e8831f12b4ef92d573bccd73392a626b3c46de1dae45f60` |

The pinned Nix shell ran these commands from the clean source commit:

```sh
python3 tool/reader/native_package.py sources "$artifact/source"
bash tool/bookfin build-android
cp build/app/outputs/flutter-apk/app-debug.apk "$artifact/bookfin-d8e1021-arm64-debug.apk"
python3 tool/reader/native_package.py verify "$artifact/bookfin-d8e1021-arm64-debug.apk"
python3 tool/reader/ocr_package.py verify "$artifact/bookfin-d8e1021-arm64-debug.apk"
"$ANDROID_HOME/build-tools/36.0.0/zipalign" -c -P 16 4 "$artifact/bookfin-d8e1021-arm64-debug.apk"
"$ANDROID_HOME/build-tools/36.0.0/apksigner" verify --verbose --print-certs "$artifact/bookfin-d8e1021-arm64-debug.apk"
"$ANDROID_HOME/build-tools/36.0.0/aapt2" dump badging "$artifact/bookfin-d8e1021-arm64-debug.apk"
```

where

- `artifact` is the absolute artifact directory named above.
- `ANDROID_HOME` is the SDK root supplied by the pinned Nix shell.

Every command exited successfully. The build uses the normal `lib/main.dart`
entry point. Package metadata identifies `dev.bookfin.bookfin` and ARM64 only.
The verifiers establish the pinned PDFium library, 29 notices, bundled English
model, native libraries, debug signature, 16 KiB alignment, and clean provenance.
`source-export.txt` inventories the source archive and dependency source bundles.
The APK's bundled provenance matches the source commit and source archive hash.

Gradle used this worktree's private `.cache/gradle` home, with cloned dependency
caches but no shared daemon registry. Its properties disabled persistent daemons
and ran Kotlin compilation inside Gradle. The exit trap ran `./gradlew --stop`
only against that private home. It reported no Gradle daemons. The final process
check found no Gradle or Kotlin compiler daemon. Build output stayed in files.
The existing combined artifact directory in main was not changed.
No install, relaunch, device inspection, or Android acceptance occurred.
The parent handles independent review, integration, and device acceptance.
