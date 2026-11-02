# Integrated Android and real Jellyfin observations

The bounded follow-up from main `03ac7f5`, including the parent's later correction,
is recorded in `final-head-android.md` and `final-head-observations.json`.
That follow-up identifies its own final APK and repeats disconnected playback;
the earlier APK observations below are not reused as proof of that build.

Date: November 2, 2026. Starting main: `d9bc3a600bec308a25c30c0e1ba9282ad21d0b7d`.
Tickets: `boo-sthf`, `boo-2cgp`, and the runtime correction `t0-dqxp`.
The parent owns review, integration, acceptance, and ticket closure.

## Environment and evidence boundaries

This worktree created its own pinned Jellyfin 12.4.0 core-only fixture.
It used only generated accounts, generated AAC audio, and the generated EPUB.
The server listened on `127.0.0.1:7364`. No production server or credentials were used.
The private restartable fixture remains ignored under `.cache/sync/runtime`.

Android used T3 host `local`, device `emulator-5554`, and this thread's own device binding.
All launches, input, settings, simulated calls, and screenshots used that binding.
ADB was used only for installation, reverse forwarding, and diagnostic reads.
No browser, child agent, global toolchain installation, coverage, or mutation job ran.

The Android app connected through the checkout-local observer on loopback port 7365.
Its upstream was the actual Jellyfin fixture on port 7364, not `tool/playback_fixture.dart`.
The observer forwarded requests and original response bytes without adding a file validator.
It recorded response status and allowlisted playback fields, never authentication headers or login bodies.
A temporary delay made small real downloads observable. One explicitly marked HTTP 503 was injected.
That injection proves cancellation after a file failure, not a Jellyfin policy failure.

The existing evidence publisher independently ran all nine live application checks before publishing `app-http.json`.
Its runner-success and cleanup requirements remain unchanged.
The Android observations in this document are manual runtime evidence, not additional publisher-certified checks.
The live suite still does not exercise Android secure storage or emit playback reports.
`integrated-observations.json` retains allowlisted real response fields and selected Android playback states.
It separates observations before and after the final native correction installed at 07:58:50 UTC.
It includes the final APK hash and the native patch hash, not credentials or complete Android diagnostic dumps.

## Account and catalog observations

| Action | Observed result |
| --- | --- |
| Sign in through the production screen as ordinary `research-alice` | Only book libraries were offered. The accessible music library was excluded. |
| Restart the application process with app data retained | The selected public library and books returned without password entry or another authentication request. Real `/Users/Me` requests succeeded. |
| Inspect matching public titles | Four audio editions and one EPUB initially appeared as separate books. Matching names did not merge them. |
| Link editions through the confirmation screens | The user-visible work retained separate audio editions and an ebook edition. Cancelling the ebook confirmation preserved the separate ebook. Confirming it paired the ebook. |
| Combine the first two Recording A sources | One audio edition contained two ordered files. The alternate recording and third source stayed separate. The file-order screen was available. |
| Sign out during a simulated call interruption | The account, selected recording, and native playback disappeared. Returning focus did not restart audio. Restarting the process still showed sign-in. |
| Sign in as ordinary `research-bob` | Only the public book library was offered. Alice's book corrections, downloads, and selected resume were absent. Downloads showed no downloads. Listening requested a downloaded edition. |
| Restart Bob, then return to Alice through sign-out and sign-in | Bob's account survived restart. Alice's grouped catalog, two-file download, ebook download, and paused resume returned only after Alice signed in. |

These observations exercise the installed Android credential store, not the live suite's test-only disk credential store.
They do not prove behavior behind a credential-locked Android screen.

## Download observations

| Action | Observed result |
| --- | --- |
| Start a delayed two-file download, then restart the process | Downloading resumed visibly. The observed prefix changed from 266,240 bytes before restart to a fresh 200,704-byte prefix afterward. |
| Cancel that restored transfer | The screen changed from Downloading to Not downloaded with Retry. After another process restart, 315,392 retained bytes stayed cancelled. |
| Remove that restored cancelled transfer | Confirmation removed the entry. Downloads showed No downloads yet. |
| Inject failure for the first source while the second remained active | The screen showed the sanitized failure plus Downloading, 0 / 2 files, and a usable Cancel button. |
| Cancel after that early-file failure | Both sources lost acquisition intent. After restart, 73,728 retained bytes remained cancelled. No later source restarted automatically. |
| Clear the injection and explicitly Retry | The recording completed with 796,707 / 796,707 bytes and 2 / 2 files. |
| Download the explicitly paired EPUB | The ebook completed with 1,221 bytes and 1 / 1 files. |
| Read the installed app's completed files for diagnostics | Each complete file matched its fixture original and saved SHA-256 digest exactly. No file was inserted into Android storage by the test. |

SHA-256 is a hash of a file's exact bytes.
The two audio originals contained 398,673 and 398,034 bytes.
The EPUB contained 1,221 bytes. Their observed hashes are in `integrated-observations.json`.
All three files were acquired through Bookfin's normal Download operation.

The server omitted a strong HTTP ETag. The observer did not manufacture one.
Retry used complete HTTP 200 downloads without Range or If-Range prefix reuse.
This proves safe restart recovery, not real-server range resume. `t7-bzzg` stays open.

## Playback, native controls, and reports

A recorded position measures source audio, not wall-clock listening time.
Each audio source lasts 180,000 recorded milliseconds. The ordered edition lasts 360,000 recorded milliseconds.
A Jellyfin tick is one ten-millionth of a second. One recorded millisecond equals 10,000 ticks.

| Action | Observed result |
| --- | --- |
| Listen to the downloaded recording | Real Android playback began. No additional media download occurred during playback. |
| Select Ending in the first source | The whole-edition position became 90,000 milliseconds. The chapter belongs to the first source. |
| Select the second source's file-start entry while paused | The whole-edition position became 180,000 milliseconds, with zero source-relative milliseconds. Playback stayed paused. |
| Set 1.5x speed | Android published speed 1.5. Stored and reported positions remained recorded-time positions. |
| Use Android's notification Pause and hardware rewind/fast-forward | Playback paused. The native recorded position moved by exactly minus 10,000 and plus 30,000 milliseconds. |
| Repeat native Pause after the last correction, then restart | Native position advanced from 91,554 to a paused 95,081 milliseconds. Process restoration retained exactly 95,081 milliseconds. No zero-time pause report appeared. |
| Play through a real file boundary on the final corrected decoder | Jellyfin accepted the first source stop at 1,799,530,000 ticks and the second source start at 850,000 ticks. Each response was HTTP 204. |
| Interrupt with a synthetic call, then end the call on the final APK | Android changed to PAUSED at 274,548 milliseconds, then returned to PLAYING at 304,538 milliseconds without a user Play command. |
| Press native Stop while focus remained lost, then end the call on the final APK | Android stayed NONE at 308,314 whole-edition milliseconds rather than restarting. |
| Sign out while focus remained lost, then end the call on the final APK | Android changed from PAUSED at 9,175 milliseconds to NONE at zero and default speed. The app stayed signed out after process restart. |
| Set the five-minute sleep timer, lose focus, wait for expiry, then end the call on the final APK | The timer changed to off after five minutes. Android stayed PAUSED at 7,873 milliseconds before and after focus returned. Audio did not restart. |
| Disable Wi-Fi and mobile data and remove this thread's reverse forward | The existing downloaded recording still played. The server was inaccessible from the app. |
| Restart during actual offline playback on the preceding corrected APK | Native position was 260,215 milliseconds before restart. Paused restoration was 260,169 milliseconds at 1.5x. The retained sample was 46 milliseconds earlier, not a new zero position. |
| Reconnect while that restored selection remained paused | The observer's total playback-request count stayed 95 before and after reconnect. No old offline request sequence was observed. |
| Explicitly Play after reconnect | A fresh second-source start used 801,700,000 ticks, equivalent to 80,170 source-relative milliseconds. Jellyfin returned HTTP 204. |

The observer also captured real `/Sessions/Playing/Progress` and `/Sessions/Playing/Stopped` responses with HTTP 204.
Across baseline and corrected runs, it captured 19 starts, 116 progress reports, and 16 stops, all HTTP 204.
The final correction accounted for four starts, 19 progress reports, and three stops, all HTTP 204.
An authenticated read of the disposable server's own session showed the matching item, media source, paused state, and source ticks.
The request observer did not replace Jellyfin's responses.
The source and tick observations prove this disposable server's supported live-report acceptance, not full personal-record sync.
The queued-report, restoration-write, and jump scheduling races remain behavior-test evidence, not UI scheduling claims.
The final correction repeated native Pause, exact paused restoration, chapter seeking, file transition, and interruption checks.
The fully disconnected playback/reconnection run preceded the last Pause-position correction; it was not repeated after that correction.

## Concrete runtime correction

The original APK emitted a zero-time report under the previous source during a cross-file seek.
A later repeat also exposed a zero-time loading placeholder during decoder reactivation.
The native adapter correction is tracked in `t0-dqxp`.

Five regression tests first failed on behavior, not missing symbols:

1. A delayed source-index view paired the new source position with the old source identity.
2. An intermediate cross-file seek sample published the target time under the previous source.
3. Decoder reactivation published idle/loading placeholder positions.
4. Filtering those placeholders also hid a confirmed paused seek. The final regression preserves the paused seek update.
5. Decoder release briefly published zero during native Pause. The final regression retains the recorded pause position.

The corrected runtime repeat retained the previous source's last real position at stop.
The corrected reactivation began near 170,000 milliseconds without the earlier zero-time progress report.
Automatic source transition then reported source-relative time near zero for the new source only.

## Executed checks

All commands used the current pinned Nix shell. Heavy commands ran sequentially.
Private logs remain under this worktree's mode-0700 `.cache` directory.

| Command | Result |
| --- | --- |
| `flutter test --no-pub test/playback/native_test.dart --reporter expanded` | Five meaningful red runs, then all nine native-control tests pass. |
| `flutter test --no-pub --reporter expanded` | All 199 tests pass after the final native correction. |
| `flutter analyze --no-pub` | Clean after the native correction. |
| `flutter build apk --debug --no-pub` | The final corrected APK builds through the pinned shell. |
| Python unittest discovery in `tool/research/sync` | All 40 research tests pass. |
| Python unittest discovery in `tool/acceptance` | All six tests pass, including failed-runner publication refusal and five observer tests. |
| `collect_evidence.py` | All nine real-server checks pass before publication. |
| `bash test/sdk_link_test.sh` | The additive, repeated, existing-tool, and missing-SDK checks pass. |

## Cleanup

Both completed editions were removed through the production confirmation dialogs.
Downloads displayed No downloads yet. Sign-out and a process restart retained the sign-in screen.
The native media state was NONE at zero with default speed. No synthetic call remained active.
Wi-Fi and mobile data were restored to their original enabled settings through the device binding.
Only this thread's reverse forward for port 7365 was removed; the reverse list was empty afterward.

The authoritative publisher then reran all nine real-server checks successfully, including cleanup, before publishing evidence.
The own observer and Jellyfin processes exited. Neither port 7364 nor port 7365 had a listener afterward.
The ignored private fixture was retained for restart, with restricted directory and credential-file permissions.
Only this thread's device session was closed. Its Device panel binding was released with `shutdown:false`.

## Remaining original acceptance gaps

A discrete manual Pause command during already-lost focus is not independently observed. Ticket: `t0-60ea`.
The UI changes that transport button to Play during the interruption.
The bound device helper exposes a play/pause toggle, not a discrete Pause key.
Normal native Pause, interrupted Stop, interrupted sign-out, and timer-expiry Pause are separate observations.

No physical-phone output, Bluetooth/headset routing, credential-locked screen, Android Auto, or battery-stress soak is claimed.
A short emulator sleep-expiry check is not a background reliability or battery-stress claim.
Changed-source recovery remains undecided in `t8-ld5q`.
Strong-validator range resume remains undecided in `t7-bzzg`.
Full personal-record sync and historical activity replay remain outside these tickets.


## Parent correction: Pause during decoder reactivation

The review regression confirmed that Pause could publish an unconfirmed loading source/zero. LocalAudioEngine now has one confirmation rule shared by publication and Pause. It retains the last confirmed sample across loading, cancels interruption recovery with decoder Stop, and restores the confirmed decoder source/time if release changed it. A regression first failed and now verifies Pause during loading, subsequent Play at the retained position, and legitimate seeking to zero. New loads clear retained confirmation.

All 200 application tests pass; analysis is clean and changed Dart files are formatted through Nix. These are host tests, not a repeat of Android observations. The previously recorded native patch hash describes the earlier observed build; this correction has not yet been inspected on Android. Final-build offline repeat and discrete manual Pause during lost focus remain open.
