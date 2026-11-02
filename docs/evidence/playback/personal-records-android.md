# Personal-record Android acceptance attempt

The later authorized attempt on integrated main is recorded in
`personal-records-fresh-attempt.md`. It also stopped before field entry, after
an operator error in a Settings launch and its advised retry. It adds host
verification, but no playback or personal-record Android acceptance.

Date: November 2, 2026. Times below are UTC.
Source base: `72996e4fe51d43639a08127ad3fdf0f1a74ef2f3`.
Tickets: `boo-6h8w`, `boo-sthf`; follow-up: `t7-msmk`.

Result: incomplete. This run built and installed the normal application, but
stopped before sign-in under the required device-command failure rule. It does
not certify playback, personal records, or credential-locked controls. No
application regression was established, so no application code was changed.
The parent owns review, integration, and ticket closure.

## Build and source identity

The source includes implementation `14ab8c5` and reviewed corrections `ec7477e`
and `10051f6`. Application, Android, test, and tool sources have no changes from
the base. The native source-identity, intentional-zero, and interruption fixes
remain untouched. Retained-download work `t9-k4lf` was not edited.

| Artifact | SHA-256 |
| --- | --- |
| Normal application debug APK, production `lib/main.dart` entry | `745d4550d11d5d82b8e19b356b259cbb37e85c4a441cde75dba794a5f0404f2f` |
| Installed package APK, read back after installation | `745d4550d11d5d82b8e19b356b259cbb37e85c4a441cde75dba794a5f0404f2f` |
| `lib/playback/native.dart` | `03d718ce68c7cdb5f8b3f6b3d357bd7a84dc99c40662b6e5e91c910925a17be3` |
| `lib/playback/playback.dart` | `d3c5ffc3cc2806eb474fe5b5b459944d973793fa5501dd7feacc689ff82e20f2` |
| `lib/playback/records.dart` | `5d906499ba68c9e91cf84bbf89710a9499da39443f4f45a0c35e47c8969e5b3f` |
| `lib/playback/records_screen.dart` | `8875a74675c64580b110a5948f28f4ebdebf2b122df43f2f7b7dd466845ee888` |
| `lib/playback/screen.dart` | `07a252d411e1d6e126f4d75e93f0126b7ad7a3139fa54e65543c15df89e3795d` |
| `lib/playback/store.dart` | `a5ca455687f496500b88a06c859e67dff13b7a73450cac6f2e8ebb1e1ff76e23` |
| `lib/playback/reporting.dart` | `e664d7afc1a6ba84549ee1d87bbf05f06036cb083a8d3546f3e7ca02142fb30c` |
| `android/app/src/main/AndroidManifest.xml` | `0b15cc9c40ec5b46706f7ed446ccaff6319e203cf2b647e9600087dc00789b31` |
| `flake.lock` | `620ebda96a2f73ba0777e3f4f093baeb9d15dd69681c59b0b83610fbce1be2a1` |

Build commands ran sequentially through the project Nix shell:

```sh
nix develop --profile .cache/dev-shell --command bash -c 'flutter pub get >.cache/pub-get.log 2>&1 && bash tool/bookfin build-android >.cache/build-android.log 2>&1'
```

The Android ARM64 debug build succeeded. Gradle reported Java source/target 8
obsolescence warnings. An initial cache-copy optimization failed because the
shell's `cp` does not support `-c`; the build then populated its own caches.
Neither another checkout's runtime nor its build output was used as evidence.

The normal APK is ignored at `.cache/history-production.apk`; its installed
readback is `.cache/history-installed.apk`. This is a normal-app debug build,
not a release build and not an integration-test APK. No test APK was built or
installed in this run. Earlier APK hashes in `final-head-android.md` describe
different builds and do not establish this run's runtime acceptance.

## Fixture and device sequence

The owned fixture was real Jellyfin 12.4.0, core only, created from this
checkout's pinned sync shell. Preparation created two ordinary synthetic
accounts, synthetic playable audio and an EPUB, and the acceptance library
layout. Only the fixture ports were used: server `127.0.0.1:7364` and observer
`127.0.0.1:7365`. Both ports were free before startup. The owned emulator reverse
forward mapped port 7365. No production server or private user credentials were
used. The application never authenticated to this fixture.

The caller opened its own T3 binding for host `local`, device `emulator-5554`.
All UI commands used that binding's `agent-device`. `device_screenshot` was
called to inspect the device. Normal tools handled build, installation, APK
readback, diagnostic reads, and the owned port forward. No adb, simctl, or ssh
UI command was substituted.

| Time | Observation |
| --- | --- |
| Approximately 11:27 | Bookfin showed the signed-out form. Wi-Fi and mobile data were both enabled; no reverse forwards existed. |
| Approximately 11:29 | Android Security settings showed Device unlock `None`; the lock selector marked `None` as the current screen lock. |
| Approximately 11:30 | Through Android Settings, created a temporary synthetic six-digit emulator PIN and selected the offered default to show notification content. No existing credential was replaced. |
| Approximately 11:32 | Built and installed the normal application; opened its signed-out form. |
| 11:33 | Filling the server address field failed. The advised diagnostic retry also failed. Acceptance stopped. |
| Approximately 11:35 | Cleanup authenticated with the same temporary PIN, selected `None`, inspected the removal confirmation, and confirmed removal. Settings then showed Screen lock `None`. |
| Approximately 11:36 | Verified Bookfin still signed out, native session inactive, and network settings unchanged. Removed own forward, stopped own servers, and released the T3 binding without shutting down the emulator. |

## Exact stop boundary

The server-field command returned:

```text
Error (COMMAND_FAILED): Field focus was refused
Hint: Retry with --debug and inspect diagnostics log for details.
Diagnostic ID: mvz6kuqh-0f68bc2c
```

The advised `--debug` retry returned:

```text
Error (COMMAND_FAILED): Ref @e5 belongs to an expired ref frame — a device action since the snapshot invalidated it
Hint: The UI may have changed since these refs were issued, so they no longer represent current device state. Take a new snapshot before relying on or interacting with them.
Diagnostic ID: mvz6l1dp-b9394cf8
```

Its structured diagnostic reported `reason: ref_frame_expired` and
`dispatched: no`. The retry reused a reference invalidated by the earlier
action. It was not a clean reproduction of the focus refusal. A separate
attempt to target the username by an unsupported indexed selector also failed
argument validation before the diagnostic retry. These are command-execution
limits of this attempt, not demonstrated application defects. This run does
not establish that field entry or credential-locked controls are unsupported.

After the failed retry, no further acceptance actions ran. Only cleanup used
the device. No synthetic password was entered in Bookfin, and Sign in was not
pressed. The temporary PIN setup was reversible, but playback while locked was
not reached. No permission bypass, credential bypass, or alternate UI driver
was attempted. Settings navigation emitted permission-dialog hints for the
permission-controller Settings page; inspection did not lead to granting any
permission or adding a Google account.

## Outstanding runtime matrix

Source-relative milliseconds measure recorded audio from the start of one
source file. No actual playback position or personal-record store observation
was obtained in this attempt. In particular, native `NONE` at zero while signed
out is not evidence for a recorded seek to zero.

| Required observation | Result in this run |
| --- | --- |
| Ordinary sign-in and production download | Not completed; stopped at the server field. |
| One grouped slider seek and immediate Undo | Not executed. |
| Mini-player forward jump and Undo; History Pause and Undo | Not executed. |
| Bookmark creation, editing, restoration, confirmed deletion, stable position | Not executed. |
| History previous/result restores append without erasing actions | Not executed. |
| Notification seeks/Pause and interruption record meaningful actions without per-tick rows | Not executed. |
| Process restart preserves history, bookmarks, and source position | Not executed. |
| Account isolation; offline operation; reconnect avoids old live-event replay | Not executed. |
| Credential-locked media controls | Temporary credential setup and removal only; controls not exercised. |

Exact blocked-write timing remains deterministic-test evidence from preceding
work. No human-timing claim, mock-based runtime certification, coverage,
mutation testing, or research-suite rerun is added. Existing host-suite results
are not relabeled as results from this run. No code change required another
host test or analyzer run.

## Cleanup

The initial and final network reads were Wi-Fi `1`, mobile data `1`. Network
settings were never changed. Screen lock returned to its initial `None`
configuration. The final trust-manager diagnostic reported `deviceLocked=0`.
The final Bookfin snapshot showed Sign in and disabled Downloads/Listening
destinations. No downloads or application session were created by this run.
The final native diagnostic showed `active=false`, `NONE(0)`, position zero.

The owned observer PID 10734 exited after SIGTERM. The recognized fixture PID
9908 exited normally after the fixture's own stop command. Neither port 7364
nor 7365 had a listener afterward. The owned reverse forward was removed; its
final list was empty. The T3 binding was released with `shutdown: false`.
Other sessions and the running emulator were not closed.

Private synthetic fixture state, build logs, cleanup screenshots, and diagnostic
reads remain ignored under this checkout's `.cache`. Tokens, passwords, private
device dumps, and APK bytes are not committed. The acceptance tickets remain
open. `t7-msmk` tracks a fresh permitted device attempt and the uncompleted
runtime matrix; it does not assert an application bug.
