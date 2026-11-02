# Appearance foundation verification

Date: November 1, 2026, America/New_York.
Base: `a6bfc1cc82b1ce8dc1705fee5408d868a9dfb6a1`.
Branch: `t3/appearance-theme-foundation`.
Checkout: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-ebdc63e5`.
This records implementation evidence, not user acceptance or ticket closure.

## Automated evidence

All build, test, analysis, and formatting commands ran through `nix develop`.
One heavy command ran at a time.
Full validation ran these steps in order. Tests and analysis ran again after the last test additions; production code did not change.

```sh
nix develop --command bash -c '
  dart format lib test &&
  bash tool/bookfin test &&
  flutter analyze &&
  flutter build apk --debug -t lib/main.dart &&
  flutter build apk --debug -t lib/gallery.dart
'
```

| Check | Observed result |
| --- | --- |
| SDK-link safety script | Passed, including refusal to replace another SDK link |
| Flutter tests | 32 passed |
| Flutter analyzer | No issues found |
| Production Android debug build | Built successfully |
| Gallery Android debug build | Built successfully, installed, and launched |

Local log: `/tmp/bookfin-61vt-final-validation.log`.
Latest tests and analysis: `/tmp/bookfin-61vt-final-checks.log`.
The final APK is the gallery entry point at `build/app/outputs/flutter-apk/app-debug.apk`.
Both entry points use `dev.bookfin.bookfin`; rebuild before choosing a different entry point to install.

Meaningful red tests preceded the sunlight policy, preference persistence, and interface implementation.
The initial sunlight policy had nine failing behavior tests before implementation.
The initial preference controller had five failing behavior tests before implementation.
Initial widget tests failed because the controls and appearance changes were not implemented.
A later transition regression failed on actual rendered paragraph color, not only a theme constant.

Tests cover sunrise and sunset windows, missing location, manual overrides, both polar seasons, leap dates, time zones, and daylight-saving offsets.
They also cover resume, foreground recalculation, selected-location changes, system fallback changes, write ordering, read damage, and failed writes.
Widget tests retain the downloaded filter, reading size, and reading scroll offset through navigation and palette changes.
The scroll offset is the number of logical pixels above the reading viewport.
The suite passed again after adding the explicit scroll-offset assertion; log: `/tmp/bookfin-61vt-scroll-validation.log`.
The final suite also verifies that an open appearance sheet updates its polar explanation after a date change that keeps the same night palette.
Reduced-motion tests require an immediate palette/screen result and no ongoing animation callbacks after the next rendered frame.
Large-text tests use a 2.0 text scale at a 400-by-900 logical-pixel viewport.
Endpoint contrast tests require 4.5:1 text and 3:1 essential-outline ratios.
The modal transition test samples rendered paragraph and choice-label colors every 16 milliseconds through a palette change.
These checks do not replace a complete accessibility audit or user review.

## Android observations

Device: host `local`, device `emulator-5554`, virtual device `bookfin-api36`.
Every launch and interaction used this task's returned device-bound command with `--no-test-ime` on launch.
T3 `device_screenshot` and that bound command's screenshots were used for inspection.
Normal Android tools were used only for installation and bounded logs.

Observed on Android:

- The production shell contains no sample books and states that no library connection is available.
- The production Night choice survives a process relaunch.
- The labeled gallery shows cream/sepia day and warm dim night palettes.
- Outfit headings and Source Serif 4 book/reading text render from the bundled TrueType files.
- The sample string renders Latin, Greek, Cyrillic, Japanese, and Arabic glyphs without missing-glyph boxes on this emulator.
- The library and reading fixtures retain the approved information layout; unavailable audio and ebook actions remain disabled.
- Selecting the New York fixture in Automatic shows “After sunset · New York.” Selecting Tokyo at the same review time shows “Daylight · Tokyo.”
- Android's `accessibility-large` text setting wraps the navigation and content rather than causing an overflow stripe. The prior `large` setting was restored.
- With Android animation scales off, manual Night and Automatic system fallback still work. Animation scales were restored to on.

The first recording exposed an independent Material default-text animation that reduced contrast during the palette transition.
`BookfinSurface` removed that second animation owner, and a rendered-paragraph regression test now guards it.
The corrected recording is `gallery-transitions-fixed.mp4`.
The earlier `gallery-transitions.mp4` is diagnostic evidence of the issue, not final acceptance evidence.

Screenshots and recordings are local, ignored artifacts under `.cache/appearance-evidence/` in this checkout:

| File | Evidence |
| --- | --- |
| production-day.png | Honest disconnected production shell |
| production-night-relaunch.png | Persisted manual Night after relaunch |
| gallery-day.png | Day library treatment |
| gallery-night.png | Night library treatment |
| gallery-fonts-day.png | Bundled typefaces and system fallback sample |
| reader-day.png | Reading typography and disabled unavailable actions |
| player-day.png | Player treatment, history section, and honest disabled transport controls |
| gallery-large-text.png | Android accessibility text scale |
| gallery-transitions-fixed.mp4 | Corrected palette transitions |
| gallery-transitions-fixed-sheet.png | Bounded contact sheet of the corrected recording |

## Browser observations

The current gallery runs on `http://127.0.0.1:7358`, not the old setup shell on port 7357.
The server binds only to loopback.
The shared T3 browser showed the gallery at 412 by 915 CSS pixels.
Its system-appearance override switched the automatic no-location gallery from day to night.
A web hot reload completed in 681 milliseconds after the rendered-text correction.
This is browser hot reload evidence, not Android hot reload evidence.

Outfit and Source Serif 4 load from local assets.
Flutter web also fetched Roboto and Noto framework fallback fonts from `fonts.gstatic.com`.
Ticket `te-6x43` tracks removing that secondary browser dependency.
Do not claim that the browser renderer is fully offline.

## Limitations and follow-up

Production city input was incomplete at this foundation checkpoint, not blocked on a new product decision.
Ticket `te-kzht` implements the already approved offline selected-city route. Its evidence is recorded separately in `docs/verification/te-kzht.md`.
The gallery city fixtures remain development samples, separate from the production search.
No location package, precise/background permission, or remote location service is required.
The current production flow and dataset limitations are in `docs/appearance.md` and `docs/city-data.md`.

The Android startup resources follow system light/dark appearance until Flutter loads the stored choice.
No native application night-mode override was added.
The foreground sunset calculation is approximate and updates within 30 seconds of its calculated horizon crossing.
No background alarm is claimed or needed for the hidden interface.

A bounded Android debugger attachment printed “Connecting to the VM Service is taking longer than expected...” twice.
A VM service address appeared while lowercase `d` detached that attempt.
No reconnect loop or Android debugger remains running from this task.
Android hot reload was not verified; ticket `t3-4isz` remains open for the parent to coordinate.

Phone text entry and phone browser access remain unverified under `boo-a4gi`.
No Jellyfin connection, playback, downloads, real ebook parsing, or sync was implemented or claimed.
The parent coordinates user acceptance, coverage, mutation testing, and final ticket closure.

## Active review handles

The Device panel remains open on host `local`, device `emulator-5554`.
The bound automation session is `t3-c377df667eb54677e6c6d077`.
Its command is `/Users/alexispurslane/.t3/userdata/device/targets/t3-c377df667eb54677e6c6d077/agent-device`.
That binding belongs to this task; another agent must call `device_open` for its own binding rather than borrowing it.
Ask this task to release its own session if a later wave needs the automation lease released.
The emulator remains booted, the installed target is the development gallery, and the debugger is detached.
Appearance is Automatic with no selected location; Android system appearance currently gives the day palette.
The original `large` text category and normal animation scales are restored.
No recording remains active.

The browser tab is `tab_4_41842020-cae3-49e1-8112-034559a9b773`.
It shows the gallery's night palette through the browser's dark system-appearance override at a 412-by-915 CSS-pixel viewport.
The loopback server on port 7358 is process `27437`, with terminal session `69780`.
It runs from this checkout with target `lib/gallery.dart` and remains available for review.
The old port 7357 session and the six saved T3 scripts were not changed.
