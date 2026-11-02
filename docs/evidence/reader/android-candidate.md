# Android EPUB candidate: download succeeds, reading is blocked

Date: November 2, 2026. Times below use UTC.
Candidate: `d9d238b0c140044143bf5b3e96b9a1371490a375`, including `3d0da65`.
Tickets: `boo-9wgg`, `t3-9r9u`, and `td-7yxu` remain open for integration and acceptance.
New application blocker: `tb-zqvc`.

This is a fresh, explicitly authorized Android attempt after the earlier device stop.
The normal application completed sign-in, library selection, EPUB download, and the Read action.
Read displayed a format refusal instead of chapter text. No readable chapter was observed.
This report does not accept the reader, the package, or corrections made after this candidate.

## Exact artifact

An APK is an Android installation file. SHA-256 identifies its exact bytes.

| Artifact | SHA-256 |
| --- | --- |
| Candidate APK copied from the implementation checkout | `c1380e6caee8fbdb782a878c920f900463fdd74239a8dff2b8bc58f472ee2ff6` |
| Installed APK read back from Android | `c1380e6caee8fbdb782a878c920f900463fdd74239a8dff2b8bc58f472ee2ff6` |
| Generated EPUB original | `6efe84b320af9a0f9997dfc6c54b172bc982e6b06978a2c3d75359161da0ce96` |
| Downloaded original read back from app-private storage | `6efe84b320af9a0f9997dfc6c54b172bc982e6b06978a2c3d75359161da0ce96` |

The APK came from `/Users/alexispurslane/.t3/worktrees/bookfin/t3-2e0ac911/build/app/outputs/flutter-apk/app-debug.apk`.
That checkout was clean at the named candidate. Its recorded artifact hash matched the source APK before copying.
The existing `tool/evidence/reader/android-build.txt` records the successful normal ARM64 debug build.
`tool/bookfin build-android` uses Flutter's normal `lib/main.dart` entry, not a test entry.
The installed package was `dev.bookfin.bookfin`, version `0.1.0`, version code `1`, minimum Android SDK `24`, target `36`.
The APK contained 128,419,613 bytes. Installation succeeded, and installed APK readback matched.
No new APK build ran in this attempt.

The prepared acceptance checkout merged the candidate without touching another checkout.
Only ticket notes conflicted. Both notes were retained, and an immediate follow-up commit removed conflict markers left during resolution.
Application, Android, package, dependency, and Nix sources remained identical to the candidate.
No implementation correction or response rewriting enabled the reader.

Manifest inspection found the existing Internet, network-state, wake-lock, foreground-service, and media-playback foreground-service permissions.
It also found the app's non-exported receiver permission. No media-storage permission appeared.
This inspection does not prove WebView request enforcement or release packaging safety.

## Fixture and device

The attempt used host `local`, Android emulator `emulator-5554`, and a fresh own T3 binding.
All launches, field entry, navigation, and saved screenshots used the returned device-bound `agent-device` command.
T3 `device_screenshot` also inspected the display.
ADB was restricted to installation, APK/file readback, process identification, and reverse-forward inspection/setup/cleanup.
No other binding, shared app-data reset, Settings activity, PIN, private book, or production service was used.

Both ports were free before startup. Own Jellyfin core `12.4.0` listened on `127.0.0.1:7364`.
The existing observer listened on `127.0.0.1:7365` and forwarded real Jellyfin responses without format metadata injection.
The app connected through an own reverse forward, which routes the emulator's TCP port `7365` to the host's TCP port `7365`.
No public listener was created. The app displayed `Wi-Fi · Media transfers allowed`.
No media-data override, radio, accessibility setting, or other device configuration changed.

The existing fixture scripts created synthetic accounts, libraries, and media.
The signed-in account was an ordinary user, not an administrator.
`tool/acceptance/reader_fixture.py` replaced only this checkout's synthetic EPUB before the app downloaded it.
The EPUB has two generated English chapters, local contents links, local PNG and JPEG squares, and the existing licensed Source Serif 4 font.
The search destination contains `starfish`. The fixture has no private or externally hosted book content.
Generated credentials, tokens, server state, APKs, and raw logs remained ignored under `.cache`.

## Actual Android observations

| Case | Observed result | Screenshot |
| --- | --- | --- |
| Sign-in and book library | Ordinary-user sign-in succeeded. Synthetic public was selected, then Ebooks showed Synthetic Work. | `images/android-candidate/01-ebook-library.png` |
| Original EPUB download | Download completed at 135,959 bytes, 1 / 1 files. The observer recorded a real HTTP 200 Download response with the same length. | `images/android-candidate/02-downloaded-epub.png` |
| Actual production Read | Read opened the reader screen but displayed “Choose a single-file EPUB edition. Other formats are not supported by this reader.” Contents, search, font size, bookmark, and page controls were disabled. | `images/android-candidate/03-reader-refuses-real-jellyfin-epub.png` |
| Process relaunch | Native process ID changed from `3121` to `4631`. The app retained sign-in and the complete EPUB download. The app returned to the library, not to a reading location. | `images/android-candidate/04-download-retained-after-restart.png` |
| Explicit own-file cleanup | Remove and its confirmation removed the only downloaded edition. Downloads showed no downloads and no retained files. | `images/android-candidate/05-own-download-removed.png` |

The generated original and downloaded file matched byte for byte by SHA-256.
The format refusal happened before a chapter viewport opened. The appearance of reader controls alone is not working reading behavior.
The cream theme in screenshot 03 is the reader's error screen, not a rendered book page or an applied publication font.

## New blocker and reproduction

The real Jellyfin catalog response omitted both `Container` and `MediaSources` for its `Book` item.
The public filtered evidence is `android-candidate-catalog.json`. Its presence flags distinguish absent fields from explicit nulls.
The same ordinary user's catalog request used the production field selection, not a simplified fake response.
The item was the actual EPUB whose original bytes downloaded successfully.

Relevant candidate code in `lib/reader/session.dart` is:

```dart
      if (selected.files.length != 1 ||
          selected.files.single.container.toLowerCase() != 'epub') {
        throw const FormatException(
          'Choose a single-file EPUB edition. Other formats are not supported by this reader.',
        );
      }
```

where

- `selected` is the ebook edition chosen through Book details.
- `selected.files` is that edition's list of original source files.
- `length` is the number of source files. This edition has one.
- `single` returns the sole source file after the first condition allows it.
- `container` is the source file's format label.
- `toLowerCase()` converts that label to lowercase before comparing it with `epub`.
- `FormatException` carries the message shown on the actual reader screen.

The corresponding format assignment in `lib/catalog/model.dart` is:

```dart
        container:
            source['Container'] as String? ??
            item['Container'] as String? ??
            '',
```

where

- `container` is the source file's format label.
- `source` is the server's media-source record, or the catalog's unnamed-original placeholder when no media sources exist.
- `item` is the server's catalog item.
- `Container` is the optional format field in either server record.
- `??` chooses the next value when the preceding value is null. The final value is an empty string.

Reproduce in a fresh disposable fixture, with ports `7364` and `7365` free:

1. Merge the named candidate into a prepared checkout, or use its exact verified APK.
2. Through `nix develop ./tool/research/sync`, run the existing fixture prepare, serve, wait, and seed commands with `BOOKFIN_SYNC_CORE_ONLY=1`.
3. Run `tool/acceptance/jellyfin_fixture.py`, then `tool/acceptance/reader_fixture.py` in that shell. Refresh only this disposable Jellyfin library.
4. Start the existing `tool/acceptance/android_proxy.py` observer. Use an own emulator route for port `7365`.
5. Use a fresh T3 device binding and launch the normal package. Enter the generated ordinary-user credentials privately.
6. Select Synthetic public, select Ebooks, open Synthetic Work, press Download, then press Read.

Do not forge `Container` in observer responses or bypass the normal source selection to claim acceptance.
The application needs a correction and another named-build acceptance attempt.

## Route observation

The own route was present before the first launch's server interactions, before Download, and before process relaunch.
At `17:24:53` the route existed and process ID was `3121`.
At `17:25:11`, after `open dev.bookfin.bookfin --relaunch`, the same route existed and process ID was `4631`.
The route was present again before Refresh books. The observer recorded successful real catalog requests after relaunch.
No route repair was needed. This single relaunch did not reproduce the earlier missing-route failure.
It does not establish why that earlier route disappeared or prove stability across repeated relaunches.
`td-7yxu` remains open.

## Unobserved cases and known candidate limits

No chapter rendered, so all cases below remain blocked rather than passed:

- First readable chapter and local PNG/JPEG/font rendering.
- Contents destinations, internal links, next/previous pages, and search-hit navigation.
- Font sizing, publication font application, reading theme, and Android large text.
- Current reading location, reading bookmark creation, reopening, and process-death reading resume.
- Offline chapter use and offline reader restart.
- Native WebView request denial, navigation interception, permission denial, and controlled adversarial EPUB behavior.
- TalkBack reading order and focus.

No adversarial external service was contacted. No TalkBack setting changed.
Host engine tests from the implementation are separate evidence and do not substitute for these Android cases.
The downloaded fixture passed ZIP checksum inspection, and its five XML documents were well formed.
These structural checks do not establish publication admission, rendered layout, or Android WebView enforcement.
Known findings R1 through R4 were not retested or claimed corrected. This attempt used their pre-correction candidate.
No coverage, mutation testing, reviewer, child agent, host-suite rerun, PR, product approval, or ticket closure occurred.

## Execution notes

One field-entry selector returned `Error (INVALID_ARGS)` because its syntax was invalid.
The error said: `Target "label="" role=text-field editable=true nth=1 research-alice" is not a @ref, selector, or "x y" point.`
The hint requested argument/help inspection. Help and a fresh snapshot were read, then one retry using the observed `@e6` reference succeeded.
Diagnostic ID: `mvzizt2w-1ff007f5`. No replacement binding or repeated failed retry followed.
Password entry used stdin without `--record-as`. Private fill output was not committed.

Preparatory shell commands also found that `apply_patch` and `aapt` were not on the login-shell path.
The provided patch executable and the Nix SDK's build-tools executable were then used directly.
A repository search named a nonexistent `lib/jellyfin` directory and was corrected using the actual catalog files.
These shell issues did not drive the device or establish application behavior.

## Cleanup and retained evidence

The app's explicit Remove download confirmation removed this attempt's only downloaded edition.
An app-private file listing at `17:31:10` found no files under `files/bookfin-media`.
Sign out returned the app to empty input fields with account-only destinations disabled.
Screenshot `images/android-candidate/06-cleaned-signed-out.png` records that state.
No shared app-data reset occurred, and account-scoped preferences were not erased.

Own Jellyfin PID `57701` accepted authenticated shutdown and exited with status zero.
Own observer PID `60691` received SIGTERM and exited with status `143`.
Neither port had a listener afterward. The own `tcp:7365` route was removed, and the final reverse-forward list was empty at `17:31:15`.
No other server, route, process, or checkout was changed.
The own binding was released with `shutdown: false`; the emulator stayed booted.
No accessibility, radio, text-size, network-policy, or credential-lock configuration needed restoration because none changed.

Public text contains only filtered synthetic metadata, request paths without query strings, and hashes.
Screenshots show no credentials, tokens, production server, or private books.
All six screenshots were visually inspected, and a private-value scan found no generated passwords or account tokens in retained public text.
`tool/evidence/reader/android-candidate/screenshots.sha256` records the screenshot hashes.
The normal candidate APK remains installed for provenance, not as an accepted release.
