# Android acceptance attempt for boo-zyx1 and boo-737n

The attempt stopped because Device panel screen inspection failed twice.
Neither ticket received device acceptance.
The first failed screenshot was followed by the advised device discovery and one screenshot retry.

## Checkout and device

| Fact | Observation |
| --- | --- |
| Acceptance base and source HEAD | `0643cebc21fb13079f82e453d558d58a551ad546` |
| Branch | `t3/verify-android-device-fixes` |
| Checkout | `/Users/alexispurslane/.t3/worktrees/bookfin/t3-15fac808` |
| Initial cleanliness | `git status --porcelain=v1` returned no entries |
| Assigned device | Host `local`, device `emulator-5556`, name `bookfin-api36` |
| Device type | Android emulator, booted, not physical hardware |
| Agent version | `0.21.31` |
| Hub version | `0.19.0-canary-20261023-1357114` |
| Launch time | 2026-11-13 03:00:08.988 through 03:00:14.914 UTC |
| Evidence commit | Reported in the handoff; no application source changed |

No checkout was created, switched, or reset.
No child agent, build, test runner, coverage job, or mutation job ran.
There was no competing heavy command while the parent ran the Flutter suite.
The initial host load averages were 30.46, 21.95, and 20.36.
The parent later reported a host load of 75 and a two-worker build limit.
No Gradle worker or other heavy command started in this attempt.
No other process was stopped.

## Exact device operations

The following tool calls and shell commands ran in this order.
The shell commands used the exact executable returned by `device_open`.

1. `device_open({"hostId":"local","deviceId":"emulator-5556"})` succeeded.
2. `/Users/alexispurslane/.t3/userdata/device/targets/t3-bdbd965bfc55eb8afbd9f3f6/agent-device help` exited 0.
3. `/Users/alexispurslane/.t3/userdata/device/targets/t3-bdbd965bfc55eb8afbd9f3f6/agent-device open dev.bookfin.bookfin --foreground` exited 0.
4. `device_screenshot({"hostId":"local","deviceId":"emulator-5556"})` failed.
5. `device_list({"hostId":"local"})` reported the host ready and the assigned emulator booted and already open.
6. `device_screenshot({"hostId":"local","deviceId":"emulator-5556"})` failed again.

Both screenshot responses gave this exact error:

> Device screenshot failed: The device hub could not complete the request. Call device_list to check the device state, and device_open if it needs to be reopened.

Device discovery showed no need to reopen the binding.
The single advised retry failed, so the agent stopped device work under the task's explicit rule.
No alternate screenshot path or device/session was used.

The launch returned a nine-node accessibility snapshot.
Its labels included `Scan`, `Fixture`, `Night`, `20`, and `View: pageWords`.
The existing app was a reader fixture, rather than an observed production-library screen.
Its installed build identity was not established.
Opening this app does not prove that either integrated fix ran.

## Acceptance results

“Unverified” means that this attempt did not observe the required behavior.
It does not mean that the product failed.

| Ticket or setup | Requirement | Result | Evidence or limit |
| --- | --- | --- | --- |
| Setup | Clean checkout at the requested base | Pass | Git identity and empty initial status |
| Setup | Open the assigned emulator through T3 | Pass | Bound command and launch events |
| Setup | Inspect the screen through Device panel | Fail | Two identical screenshot errors |
| boo-zyx1 | Start native audio playback | Unverified | Stopped before fixture setup |
| boo-zyx1 | Remove Bookfin from Recents while audio continues | Unverified | No Recents action or Activity destruction observed |
| boo-zyx1 | Reopen with the surviving Flutter engine | Unverified | No lifecycle transition or engine logs captured |
| boo-zyx1 | Turn Wi-Fi off and on after reopening | Unverified | No radio setting changed |
| boo-zyx1 | Observe a Wi-Fi-only download pause and resume | Unverified | No transfer started |
| boo-zyx1 | Observe channel connectivity owned by HostPlugin across Activity destruction | Unverified | No runtime engine/channel logs captured |
| boo-737n | Execute the compiled Android CPU guard | Unverified | No new APK installed or native speech call made |
| boo-737n | Produce words from a real fixture window | Unverified | No speech window ran |
| boo-737n | Observe no unsupported-instruction warning and no crash during that window | Unverified | No speech window or logcat capture |
| boo-737n | Reject unsupported ARMv8.0 hardware safely | Unverified | No physical Android hardware appeared in discovery |

The device list contained four booted emulators and three stopped emulator definitions.
It contained no Pixel 8 or other physical Android device.
The six CPU features recorded earlier in boo-737n were not reread during this attempt.
Earlier unit and disassembly evidence remains earlier evidence, not a result of this run.

## Existing setup examined

The agent read `AGENTS.md`, `docs/plans/bookfin.md`, both tickets and their prior evidence.
The agent also read `tk ready`, the epic dependency tree, and each ticket's dependency tree.
Both tickets were already `in_progress` and had no unresolved dependencies.

The following sources were inspected before any setup changes:

- `tool/acceptance/README.md` describes a disposable Jellyfin server and a loopback-only Android proxy.
- `tool/download_fixture.dart` serves synthetic transfer bytes with range support. Its audio bytes are explicitly not playable.
- `tool/playback_fixture.dart` serves playable synthetic WAV files and records playback requests.
- `tool/acceptance/run_interrupted_pause.sh` and `integration_test/interrupted_pause_test.dart` show the existing native playback integration pattern with temporary storage.
- `integration_test/ocr_layout_test.dart` shows the Android integration-test pattern for real native work.
- `test/speech/speech_test.dart` uses `test/speech/fixtures/alice.mp3` and expects recognized Alice words from an eight-second window.
- `test/speech/decoder_test.dart` documents the generated narration fixture and native decoding tests.
- `tool/research/cross_edition/README.md` documents a separate speech prototype. It does not establish execution of the production CPU guard.
- `tool/bookfin` and `flake.nix` define the pinned build commands and Android dependencies.

No new fixture or runner was built.
No fixture server, reverse port forward, or private account was created.
No existing app user data was cleared.
Fixture isolation was not exercised, so its runtime safety remains unverified.

## Tool capability boundary

The bound command proved that it can open the installed app and return its accessibility snapshot.
The general help listed settings and gesture commands.
This attempt did not establish a working Recents-removal command or a working Wi-Fi toggle.
No background action or force-stop was substituted for Activity destruction.
No claim about continuing audio or channel survival follows from the successful initial launch.

## Evidence and cleanup

| Artifact | Contents |
| --- | --- |
| [device-attempt.json](device-attempt.json) | Checkout facts, exact operation sequence, both failure responses, and complete discovery response |
| [agent-device-events.ndjson](agent-device-events.ndjson) | Original session events for the successful app-open command |
| Screenshot paths | None. Both capture attempts failed |
| Android logcat paths | None. Device work stopped before capture |
| Build or test log paths | None. No build or test ran |

The agent started no background process and left no owned command running.
The emulator and binding remain open.
The agent did not close the pre-existing app or another session after the required stop.
The only app action was the initial foreground open.
No taps, text entry, playback action, network change, relaunch, install, or data reset followed it.
The agent used no adb, simctl, or ssh device action.

## Follow-up

New ticket `t1-dth0` records the repeated Device panel screen-inspection failure.
An earlier single screenshot failure in `boo-gxm8` recovered on retry. This attempt did not.
Once the device tool works, a fresh authorized run must complete both acceptance sequences.
Both `boo-zyx1` and `boo-737n` remain open for the parent to integrate and close.
