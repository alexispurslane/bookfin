# Fresh Android attempt stopped before field entry

Date: November 2, 2026. All times below are UTC.
Source: integrated main `756ae5fcf77f8d1f9d18124311fedbc085c7605b`.
Tickets: `t7-msmk`, `boo-6h8w`, `boo-sthf`, and `t9-k4lf`.

Result: incomplete. The fresh attempt stopped after a failed Settings command
and its single advised diagnostic retry. My malformed activity argument caused
this failure. This is not a Bookfin defect or evidence that Android Settings
cannot open. The fresh attempt did not reach field entry, sign-in, or playback.

The normal application built successfully. All 271 host application tests passed.
These results do not replace the unperformed Android acceptance observations.
No application code changed. No sibling fresh-start change was used.
The orchestrator owns integration, user acceptance, and ticket closure.

## Source and artifact identity

The worktree started clean at the source commit above. Application, Android,
test, tool, and Nix sources stayed unchanged throughout the run.
An APK is an Android installation file. The build used the normal
`lib/main.dart` entry, ARM64 Android target, and debug configuration.
No integration-test APK was built or installed.

| Artifact or source | SHA-256 |
| --- | --- |
| Newly built normal application APK | `9532d93d5daa422f2c07d4873764537d0b9cb5a7a30be43922ffff4f6faec2ef` |
| Preinstalled application APK, read back during cleanup | `745d4550d11d5d82b8e19b356b259cbb37e85c4a441cde75dba794a5f0404f2f` |
| `lib/main.dart` | `0de79dc7bfabb6d8495e985afacad646c58b6e2e0737714b892551eb56f0357f` |
| `lib/playback/native.dart` | `03d718ce68c7cdb5f8b3f6b3d357bd7a84dc99c40662b6e5e91c910925a17be3` |
| `lib/playback/playback.dart` | `d3c5ffc3cc2806eb474fe5b5b459944d973793fa5501dd7feacc689ff82e20f2` |
| `lib/playback/records.dart` | `5d906499ba68c9e91cf84bbf89710a9499da39443f4f45a0c35e47c8969e5b3f` |
| `lib/playback/records_screen.dart` | `8875a74675c64580b110a5948f28f4ebdebf2b122df43f2f7b7dd466845ee888` |
| `lib/playback/screen.dart` | `07a252d411e1d6e126f4d75e93f0126b7ad7a3139fa54e65543c15df89e3795d` |
| `lib/playback/store.dart` | `a5ca455687f496500b88a06c859e67dff13b7a73450cac6f2e8ebb1e1ff76e23` |
| `lib/playback/reporting.dart` | `e664d7afc1a6ba84549ee1d87bbf05f06036cb083a8d3546f3e7ca02142fb30c` |
| `lib/downloads/downloads.dart` | `c9bd74be43e054d9865e32e9aab5dd50e9159f5f1af9c91e109c9dee2ec66ec9` |
| `lib/downloads/screen.dart` | `0a3a90e8595c01cba3e17bdbaade93610f4ad74529033d1b0584dfda01680d65` |
| `lib/catalog/screen.dart` | `8c65a61a831eddca2ce8c763a47ae537bf09022476f108a1cfca6acc63a51301` |
| `android/app/src/main/AndroidManifest.xml` | `0b15cc9c40ec5b46706f7ed446ccaff6319e203cf2b647e9600087dc00789b31` |
| `flake.lock` | `620ebda96a2f73ba0777e3f4f093baeb9d15dd69681c59b0b83610fbce1be2a1` |
| Committed signed-out screenshot | `9b4c68a1fd17576c7a5246250e6243902f8c92e7aad85fb74680214380c57819` |

The newly built APK was not installed. The build finished after device
acceptance stopped and the binding was released. Its successful compilation
does not establish runtime acceptance of integrated main.

The preinstalled APK matches the earlier stopped attempt's artifact in
`personal-records-android.md`. The signed-out observation and screenshot refer
only to that preinstalled APK. No observation from it is attributed to the new
APK. APK bytes and the installed-package readback remain ignored under `.cache`.

## Fixture and chronology

The caller opened its own T3 binding for host `local`, device `emulator-5554`.
The binding was not reused from the preceding attempt. Every device UI action
and screenshot used the command returned by this binding. `device_screenshot`
also inspected the display. No alternate UI driver was used.

Only this worktree's new synthetic Jellyfin fixture was used. Both loopback
ports were free before startup. Preparation created ordinary synthetic accounts,
generated audio and an EPUB, and synthetic libraries. No production credentials
or another session's fixture state were accessed.

| Time | Action and observed result |
| --- | --- |
| Before 12:12 | Started owned Jellyfin 12.4.0 core on `127.0.0.1:7364`. Its readiness, seed, and acceptance preparation commands succeeded. |
| Before 12:12 | Opened an own binding. An initial guessed package name failed. App discovery supplied `dev.bookfin.bookfin`, and opening that exact package succeeded. |
| Before 12:12 | The preinstalled Bookfin snapshot showed Sign in, empty username/password fields, and disabled Downloads and Listening destinations. |
| By 12:12 | Started the owned HTTP observer on `127.0.0.1:7365`. No emulator reverse forward was created. |
| Before 12:14 | Initial diagnostic reads reported Wi-Fi `1`, mobile data `1`, no reverse forwards, and `deviceLocked=0`. Native Bookfin state was inactive `NONE` at zero. |
| Before 12:14 | A help request used `hardware` instead of `hardware-button`. The command's advice supplied the right name, and that help request succeeded. No hardware input was dispatched. |
| Approximately 12:14 | A Settings launch with a malformed activity argument returned `COMMAND_FAILED`. |
| 12:14:23 | Its single advised `--debug` retry returned the same failure. Diagnostics showed a nonexistent component. All acceptance actions stopped. |
| By 12:16 | Stopped both owned services. Cleanup reads showed unchanged network values, no reverse forwards, and `deviceLocked=0`. |
| Before 12:17 | Captured and inspected the safe signed-out screenshot. Read back the preinstalled APK. Released the own T3 binding with `shutdown: false`. |
| By 12:17 | The normal application build completed successfully. The new APK was not installed. |
| After the build | Ran the default application test suite, analysis, and SDK-link tests sequentially through Nix. All passed. |

The observer recorded no requests. No account authenticated through Bookfin.
No server-side playback reports were obtained. No file or record from another
account was read to manufacture account-isolation evidence.

## Exact stop boundary

The Settings launch supplied this activity argument:

```text
--activity com.android.settings.Settings$SecuritySettingsActivity
```

Both the first call and its single advised retry returned:

```text
Error (COMMAND_FAILED): adb exited with code 1
Hint: Retry with --debug and inspect diagnostics log for details.
```

The first diagnostic ID was `mvz80s9h-3696dec1`. The retry diagnostic ID was
`mvz810nu-70aa0982`. The retry printed this Android response:

```text
Error type 3
Error: Activity class {com.android.settings/com.android.settings.com.android.settings.Settings$SecuritySettingsActivity} does not exist.
```

The argument became a component with a duplicated package name. I selected an
invalid command shape. This was an operator error, not an observed application
or field-focus failure. No third attempt, new binding, alternative Settings
route, or alternate UI driver was used to evade the stop rule.

The initial package-name error was `APP_NOT_INSTALLED` for
`org.bookfin.bookfin`. Its advised installed-app discovery and exact-name retry
succeeded. The help-name error was `INVALID_ARGS` for `hardware`. The advised
`hardware-button` help succeeded. These recovered errors did not exercise
Bookfin behavior.

## Android acceptance still required

| Required observation | Result in this attempt |
| --- | --- |
| Fresh field entry, ordinary sign-in, and production download | Not executed. |
| Grouped slider drag and immediate Undo | Not executed. |
| Mini-player jumps and Undo, History Pause and Undo | Not executed. |
| Bookmark creation, editing, restore, and confirmed deletion | Not executed. |
| History previous/result restore appends without erasing actions | Not executed. |
| Explicit native Pause, seeks, and interruption actions | Not executed. |
| Process restart retains history, bookmarks, and source position | Not executed. |
| Account isolation, offline operation, and reconnect reporting | Not executed. |
| Retained-download visibility, removal, and relaunch | Not executed. |
| Credential-locked media controls | Not executed. No credential was set. |

No application regression was established. There was no behavior change to
reproduce or fix through red-green tests. No new claim is made about a real
phone, hot reload, crash recovery, full record sync, or extended playback.

## Host verification

All build and test commands used the pinned project Nix shells. Only one heavy
command ran at a time. Logs were redirected to this worktree's ignored `.cache`.
The build used `nix develop --profile .cache/dev-shell`. Later commands used
`nix develop .cache/dev-shell --command bash -c '<command>'`.

| Command inside the project shell | Observed result |
| --- | --- |
| `flutter pub get` followed by `bash tool/bookfin build-android` | Normal ARM64 debug APK built successfully in 271.6 seconds. Java source/target 8 obsolescence warnings remained. Dependency resolution reported 15 newer packages outside current constraints. |
| `flutter test --reporter expanded` | All 271 application tests passed. |
| `flutter analyze --no-pub` | No issues found. |
| `bash test/sdk_link_test.sh` | Passed additive linking, repeatability, existing-tool refusal, and missing-SDK cases in temporary directories. |
| `git diff --check` | Passed before the evidence commit. |

The private log files are `.cache/build-android.log`, `.cache/host-tests.log`,
`.cache/analyze.log`, and `.cache/sdk-link.log`. The SDK-link test did not modify
the live host SDK. No coverage, mutation, web, or real-decoder integration test
ran. These host results are new results for this source, not relabeled prior
runs.

## Screenshot and cleanup

`images/fresh-attempt-preinstalled-signed-out.png` shows the preinstalled
application, not the new main build. It contains no credentials or private
library data. Its only role is to show the signed-out state left on the emulator.

No app download, personal record, or sign-in was created. No PIN, radio state,
permission, or other Android configuration was changed. The security page never
opened, so this run does not establish a new observation of Screen lock None.
The final diagnostic reported `deviceLocked=0`. Wi-Fi and mobile data remained
`1`, matching their initial values. The final reverse-forward list was empty.

Owned Jellyfin PID `64346` exited after the recognized fixture stop command.
The server command exited with status zero. Owned observer PID `68861` exited
after SIGTERM, with its command reporting status 143. Neither port 7364 nor
7365 had a listener after cleanup. The own binding was released without shutting
down the emulator. No other session was closed or rebound.

Private synthetic server state and build logs remain ignored in this worktree's
`.cache`. No password, token, authentication body, private device dump, or APK
is committed. No child, PR, ticket closure, coverage, or mutation job was started.
All four tickets remain in progress. Another device attempt requires fresh
authorization under the device failure rule.
