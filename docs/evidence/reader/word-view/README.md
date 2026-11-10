# PDF word-view evidence

Captured on November 10, 2026 for `tb-22fu` and `te-rtfa`.
The five acceptance captures were refreshed after the three review fixes.
The before-fix image remains unchanged as failure evidence.

## Environment

The dedicated Android emulator is `bookfin-tb22fu`, device `emulator-5554` on host `local`.
Its display has 1080 by 2400 physical pixels.
The app is a debug build of `tool/reader/word_view_probe.dart`.
It uses the real PDF engine, bundled English recognition, band renderer, and `PdfViewport`.
The probe controls are test controls, not the future three-way reader choice from `tb-9mcf`.

The emulator uses this absolute SDK image path in its AVD configuration:

```text
image.sysdir.1=/nix/store/in52zy1w2yv0197h7553n827h8f03x8k-bookfin-android-sdk/system-images/android-36/google_apis/arm64-v8a/
```

Only this emulator received input. The physical Pixel 8 was not opened or used.
T3 `device_open` supplied the device-bound command for all launches, taps, swipes, and screenshots.

## Captures

| File | Source and state | Observed result |
| --- | --- | --- |
| `before-transparent-gaps.png` | Scan, before the alpha correction | Dark rectangles cover the gaps between word images. This records the Android failure, not acceptance. |
| `scan-cream-20.png` | `footnote-page.pdf`, cream paper, text size 20 | Printed word images retain their shapes and share the cream paper without opaque gaps. |
| `scan-night-40.png` | The same scan, night paper, text size 40 | Larger word images wrap into whole lines and use light ink without dark rectangles. |
| `text-layer-night-40.png` | `equation-page.pdf`, night paper, text size 40 | The text-layer fixture uses word images, including italic variables and superscripts. |
| `text-layer-cream-40.png` | The same text-layer fixture, cream paper | The first word screen remains readable after the theme changes. |
| `text-layer-next-screen.png` | A horizontal swipe from the preceding screen | The next whole-line screen shows the equation and table intact. |

The fixtures are the checked-in files under `test/reader/fixtures/reflow`.
No private book, server address, or credentials appear in these captures.
Pictures retain their original scan paper, as settled in `t8-w16m`.

## Reproduce

Run commands from the checkout. Prepare recognition files before the Android build.

```sh
nix develop --command python3 tool/reader/ocr_package.py prepare
nix develop --command flutter build apk --debug -t tool/reader/word_view_probe.dart --target-platform android-arm64
nix develop --command python3 -m http.server 8593 --bind 127.0.0.1 --directory test/reader/fixtures/reflow
```

Use a separate terminal for the loopback fixture server.
Install the APK on your dedicated emulator and forward its loopback port:

```sh
nix develop --command adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
nix develop --command adb -s emulator-5554 reverse tcp:8593 tcp:8593
```

Open that emulator through T3 `device_open`.
Use its returned device-bound command to launch `dev.bookfin.bookfin` and operate the probe.
The Fixture button switches between the scan and text-layer PDF.
The numeric button cycles the text size through 20, 40, and 14.
The Night/Cream button changes the theme.
Swipe horizontally to turn a word screen.

## Limits

These screenshots prove actual emulator rendering, not physical-device acceptance or measured frame times.
They do not prove that images arrive before recognition ends because they capture settled frames.
The held-recognition behavior tests in `test/reader/pdf_word_view_test.dart` verify that ordering and saved-place behavior.
The same tests cover cross-page turns, vertical drags, failure fallback, and device-pixel origin alignment.
Two pixel tests in `test/reader/word_pages_test.dart` failed before the alpha correction and pass afterward.
They verify that transparent source pixels leave the theme paper visible in cream and night.

`tb-valc` cropping, `tb-nkz5` trim controls, and `boo-5fcg` geometry fallback are separate parent integrations.
This checkout does not claim their combined Android acceptance.
