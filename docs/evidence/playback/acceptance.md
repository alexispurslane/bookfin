# Playback acceptance evidence

Date: November 2, 2026. Task: boo-sthf. Worktree starts at main `c13748198f0b7f73ad0ba1ec2b7ac84fbe989627`.

## Automated checks

All build, test, and formatting commands run through `nix develop .cache/dev-shell --command`. The profile was created from the current pinned flake. Its SDK contains Android 34, 35, and 36. No global toolchain was installed. Heavy commands run sequentially.

| Check | Observed result |
| --- | --- |
| Full `flutter test --reporter expanded` | 180 tests pass, including the existing 149 tests and 31 playback tests. |
| `flutter analyze` | No issues found. |
| `flutter build apk --debug` | Android debug APK builds successfully. |
| `flutter build web --release` | JavaScript build succeeds. No browser operation or preview acceptance is claimed. |
| `bash test/sdk_link_test.sh` | All additive-link, repeated-link, existing-tool refusal, and missing-SDK checks pass. |
| `dart format --output none --set-exit-if-changed` on the 15 affected Dart files | Zero changes. |
| `git diff --check` | Passes. |

Final command output is in `/tmp/bookfin-playback-verified.log` on the build host. The JavaScript build retains the existing secure-storage WebAssembly warnings and Cupertino font warning. `just_audio_web` also reports a WebAssembly interop warning. No WebAssembly support is claimed. The first fresh native dependency build reports obsolete Java 8 source/target warnings; these are dependency warnings, not a successful analysis failure.

## Meaningful red-green tests

Tests were written against callable boundaries before behavior implementation. Twelve initial playback tests failed on missing behavior, not missing symbols. Reporting and screen tests then failed on absent requests and absent usable controls. The subsequent regression tests caught concrete faults before their fixes.

| Failing behavior | Red evidence |
| --- | --- |
| Local-only ordering, missing-part refusal, position mapping, chapters, speed, durable resume, sleep, setting guards | `/tmp/bookfin-playback-red.log` |
| Correct file/media-source reports, HTTP 204 handling, no old offline-session replay | `/tmp/bookfin-reporting-red.log` |
| Usable mini-player, chapter selection, speed and sleep controls | `/tmp/bookfin-player-ui-red.log` |
| Restoration commands overwrote the saved position; sign-out could allow a late Play; book corrections left the selected title stale | `/tmp/bookfin-playback-races-red.log` |
| A late sample revived stopped native controls; advertised system seek actions did nothing | `/tmp/bookfin-media-controls-red.log` |
| Decoder failure left native play intent active | `/tmp/bookfin-native-failure-red.log` |
| Mobile live progress incorrectly depended on remote-media permission | `/tmp/bookfin-live-mobile-red.log` |
| Recording completion left native play intent active, allowing a later chapter seek to play behind a paused UI | `/tmp/bookfin-completion-red.log` |
| A failed report generated another request for every position sample | `/tmp/bookfin-report-retry-red.log` |

No coverage job, mutation job, competing hardening run, child agent, PR, or remote push runs for this ticket.

## Disposable Android fixture

`tool/playback_fixture.dart` binds loopback on an ephemeral port and generates two real PCM WAV files in memory. The acceptance run used port 61546, not the sync researcher's port 7364. The two files contain quiet, intermittent synthetic tones at 440 and 660 Hz. Both use 22,050 samples per second, one channel, and 16-bit samples. They are 90 and 120 recorded seconds long. Together they contain 9,261,088 bytes.

The fixture supplies disposable authentication, catalog metadata, current download authorization, byte-range downloads, chapters, and synthetic playback-report acceptance. No production credential, user token, or target-server request is used. The fixture is not an actual Jellyfin server. These writes prove Bookfin's request path and file mapping against the fixture, not acceptance by a particular Jellyfin deployment. A final repeat used ephemeral loopback port 56263 and the same generated media.

The app first showed two separate books. Android UI actions explicitly linked them and combined their consecutive audio files. Their similar names did not merge them. The existing downloader fetched and verified both files. It displayed Downloaded with 2 / 2 files and 9,261,088 / 9,261,088 bytes. Playback created no additional media download requests.

The first fixture version omitted the per-item metadata endpoint. Downloads correctly refused it before acquiring any media. Adding that fixture endpoint allowed the normal authorization path to succeed. No storage or authorization bypass was added to Bookfin.

## Android observations

Testing uses T3 host `local`, device `emulator-5554`, and only this thread's returned `agent-device` binding for installation, launch, input, settings, screenshots, and simulated phone actions. Native `adb` is used only for the permitted reverse-port forward and diagnostic dumps/logs.

| Action | Observed result |
| --- | --- |
| Open the verified two-file edition | Actual WAV playback advances through the first source and naturally enters the second source. |
| Read Android audio diagnostics | Bookfin owns audio focus with speech content and pause-on-duck behavior. Android reports an active mono AudioTrack at 22,050 samples per second. |
| Inspect fixture reports at the natural file transition | The first source stops near 89,950 ms. The second source starts at 20 ms, not at whole-edition 90 seconds. Item and media-source IDs change together. |
| Change playback speed | The visible player and Android media session both publish 1.5× while source positions remain recorded-audio time. |
| Disable Wi-Fi and mobile data; stop the fixture | Local chapter selection and playback remain available without a listening server or media acquisition. |
| Relaunch offline | Downloads verifies the existing files. The mini-player restores the selected recording paused, including its saved second-file position and 1.5× speed. The catalog reports that Jellyfin is unreachable without hiding the saved book. |
| Change short jumps | The UI accepts and displays 15 seconds backward and 45 seconds forward. |
| Simulate an incoming emulator call | Android assigns Bookfin `LOSS_TRANSIENT`. The media session pauses at 15,292 recorded ms. No real phone call occurs. |
| Cancel the simulated call and background the app | Playback resumes with the same source and speed. Native media-session diagnostics show PLAYING while the launcher is in front. |
| Sleep and wake the emulator | Playback remains a background Android media session. The emulator returns to its launcher because it has no enabled keyguard. |
| Open the Android notification shade | Android renders the book title, author, seek range, Pause, Rewind, Fast Forward, and Stop controls for Bookfin. |
| Pause from Android's media notification | The native session changes to paused. The helper reports its escaped-app guard because the launcher is foreground, but the Android action succeeds and the paused state is independently inspected. |
| Use hardware media rewind and fast-forward while paused | The whole-edition position changes from 176,928 ms to 161,928 ms, then to 206,928 ms: exactly the configured minus 15 seconds and plus 45 seconds. |
| Play through the recording's end, then select Return 2 | Real completion reaches 210,000 ms. On the patched APK, the chapter seek stays paused at whole-edition 120,000 ms / second-source 30,000 ms. Android reports session NONE and an idle AudioTrack. |
| Enable a five-minute sleep timer, then turn it off | The UI changes to Sleep timer on, then back to Sleep timer. Timer expiry remains a deterministic behavior test, not a background soak claim. |
| Force a final offline relaunch during active second-file playback | With Wi-Fi and mobile data off and the fixture stopped, Android reports PLAYING at whole-edition 156,149 ms and 1.5× immediately before the UI snapshot/relaunch. After relaunch, the mini-player is paused; the full player restores 157,051 ms / second-source 67,051 ms and 1.5×. Android reports session NONE rather than autoplay. The small position advance occurs between the diagnostic capture and process termination. |

`player.png` shows the real Flutter player. `native-controls.png` shows Android's own media controls, not a gallery mockup. `offline-resume.png` shows the final paused offline restoration. `live-reports.json` contains the first synthetic server's accepted requests and its two download requests. Diagnostic files on the host include `/tmp/bookfin-media-session-playing.txt`, `/tmp/bookfin-audio-playing.txt`, `/tmp/bookfin-focus-call-session.txt`, `/tmp/bookfin-focus-call-audio.txt`, `/tmp/bookfin-background-session.txt`, `/tmp/bookfin-final-offline-crash-before.txt`, and `/tmp/bookfin-final-offline-crash-after.txt`. Full global Android diagnostic dumps are not committed.

## Cleanup

The final APK was installed before the repeat. The device helper's replacement installation cleared the earlier fixture account and files, so the repeat signed in and downloaded both files again through the normal UI. This replacement installation is not the resume test: the later app relaunch preserved app data and interrupted actual playback.

After acceptance, the synthetic download was removed through its confirmation dialog and the synthetic account was signed out. Wi-Fi and mobile data were restored to their original enabled settings. Both fixture processes were stopped, and this thread's reverse forwards for ports 61546 and 56263 were removed. This thread released its own T3 device session with `shutdown:false`. No other session or shared service was closed.

## Limits and unresolved work

Physical-phone output, Bluetooth/headset routing, a credential-locked screen, Android Auto, and battery-optimization stress are not proven by this emulator run. The Android media session provides the native lock-screen/control boundary, but this emulator has no enabled keyguard. Sleep expiry is tested deterministically in the playback behavior tests; a long background timer soak is not claimed. Seek/pause history, Undo, bookmarks, and personal-record reconciliation belong to downstream tickets.

Changed-source recovery is a real unresolved product choice in `t8-ld5q`. The current safe guard retains the old record and refuses to apply it to replacement media. The parent must choose confirmed fresh start with retention, or reconciliation before listening. The current implementation does not claim that the blocked replacement has a recovery UI.

The parent owns acceptance, coverage, mutation testing, review, integration, and ticket closure.
