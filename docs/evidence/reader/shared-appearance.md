# Shared app and reader appearance

Ticket: `t8-j809`. Base commit: `1b58e76`. Host verification: 2026-11-02.

## Settled decision and scope

The user selected: “Switch the whole app; reading and the app always share one appearance setting.”
Reader Night selects global Night, and reader Cream selects global Day.
The existing app controls still offer Automatic and selected-city configuration.
The existing appearance controller owns persistence, save warnings, and retries.
No reader-local appearance override or second durable preference remains.

The application connects the reader's appearance request to its existing controller through the catalog and book routes.
The reader consumes the same resolved theme as the rest of the app.
The appearance controller, resolver, reader session, and renderer implementations are unchanged.
Reading text size, saved positions, and bookmarks stay in the existing account records.
The saved reading address is an EPUB CFI, a position inside the book content.

## Meaningful red proof

Before production changes, this command compiled and ran three new behavior tests against the existing implementation:

```sh
nix develop --command flutter test test/reader/shared_appearance_test.dart --concurrency=1 --reporter expanded
```

All three failed because the reader still owned a local override.
The failures were behavior assertions, not missing constructors or compilation errors.

| Behavior test | Observed failure before the fix |
| --- | --- |
| Reader Night changes the app and survives reopen and controller restart | Expected global Night, observed global Day after the reader toggle |
| Reader Day changes the app and survives reopen and controller restart | Expected global Day, observed global Night after the reader toggle |
| Global modes and Automatic follow system changes after a reader selection | Expected one renderer Day command, observed no command because the local Night override stayed active |

The test setup uses the real `BookfinApp`, production catalog-to-reader navigation, real `AppearanceController`, and real `LocalAppearanceStore`.
Only the shared-preferences platform implementation uses memory instead of native storage.
The direct test dependency pins that platform interface to its already locked version, `2.4.2`.
No runtime dependency version changes.

The EPUB fixture is admitted once per test and reused across opens.
This keeps the source bytes identical, including ZIP timestamps, as a real unchanged downloaded file does.

## Green proof

The two reciprocal tests exercise a reader toggle, exit, reopen, and replacement of both the appearance controller and reader session.
They read the saved appearance through a newly constructed local store.
Both tests retain the selected city, requested text size of 22 logical pixels, saved reading address, and bookmark.
The third test changes the global mode while the reader is open.
It also checks Automatic with system Day/Night changes and selects Automatic through the existing app controls.

The existing appearance-boundary tests still check one final renderer command per appearance change.
At 200 percent text scaling, requested size 22 logical pixels produces renderer size 44 CSS pixels.
At 150 percent text scaling, it produces renderer size 33 CSS pixels.
Theme and scaling changes preserve the saved reading address and requested size.
The attachment test still waits for the renderer to open before sending a later appearance update.

| Check | Command | Result |
| --- | --- | --- |
| Focused appearance tests | `nix develop --command flutter test test/reader/shared_appearance_test.dart test/reader/appearance_test.dart --concurrency=1 --reporter expanded` | 5 passed |
| SDK link, SDK platform, and native tools checks, followed by the full Flutter suite | `nix develop --command bash -c 'bash test/sdk_link_test.sh && bash test/sdk_platform_test.sh && bash test/darwin_native_tools_test.sh && flutter test --concurrency=1 --reporter expanded'` | Shell checks passed, 356 Flutter tests passed |

Analysis reports no issues, and the format check reports 10 files with no changes:

```sh
nix develop --command bash -c 'flutter analyze && dart format --output=none --set-exit-if-changed lib/main.dart lib/catalog/screen.dart lib/reader/screen.dart test/reader/shared_appearance_test.dart test/reader/appearance_test.dart test/reader/screen_test.dart test/reader/catalog_flow_test.dart test/downloads/screen_test.dart test/playback/root_history_test.dart test/catalog/screen_test.dart'
```

## Limits and parent acceptance

The WebView platform implementation records commands at the native boundary instead of running an Android WebView.
These tests prove production Flutter wiring, controller/store round trips, and commands sent to the renderer.
They do not prove Android storage durability, Android layout, process death, or device input behavior.
The renderer and its engine are unchanged, so the engine suite is not repeated for this wiring change.

No device, installation, runtime fixture, route, or server was used or changed.
The exclusive emulator remains with `bookfin-epub-final-runtime-gates-20261102-1`.
The parent must integrate this change before named-build Android theme acceptance.
That acceptance must cover Night, reader exit/reopen, process restart, retained text size and saved page, and reciprocal Day.
Coverage and mutation testing remain with the parent after user acceptance.
The ticket stays in progress for parent review, integration, and Android acceptance.
