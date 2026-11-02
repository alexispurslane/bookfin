# Current-main Android observations and stopped acceptance

Date: November 2, 2026. Times in this report are UTC.
Source: integrated main `261d50eb48dbe78288d44419d692e27268430a78`.
Tickets: `t7-msmk`, `boo-sthf`, `boo-6h8w`, `t9-k4lf`, and `t8-ld5q`.
Follow-up: `td-7yxu` records the missing emulator route at the stop.

Result: partial runtime evidence, not complete acceptance. The authorized new
attempt reached sign-in, library, download, native playback, personal records,
account switching, and retained-download removal. Fourteen public screenshots
recorded this attempt. The first four recorded the required basic path before
any Android Settings work. No Android Settings work followed.

Acceptance stopped when a navigation action and its single diagnostic retry
both failed. No replacement-audio confirmation or credential-lock claim follows
from this run. No application defect was established, and no application code
changed. The orchestrator owns integration, acceptance, hardening, and closure.

## Artifact identity

An APK is an Android installation file. SHA-256 identifies its exact bytes.
Every runtime observation in this report used the same normal debug APK.
The build used `lib/main.dart` and the Android ARM64 target, not a test entry.

| Artifact | SHA-256 |
| --- | --- |
| Built normal application APK | `82faf07dfc261fd3a2d309a97b021ed39b16f54e3e18ef9c3bd36f2f7327979c` |
| Installed package APK read back after installation | `82faf07dfc261fd3a2d309a97b021ed39b16f54e3e18ef9c3bd36f2f7327979c` |

The manifest and Gradle file established `dev.bookfin.bookfin` before launch.
The installation command succeeded. APK readback matched the built bytes.
Application, Android, test, tool, and Nix sources remained unchanged from the
source commit. No prior stopped attempt supplied runtime results for this APK.

## Fixture and device

The attempt used its own T3 binding on host `local`, device `emulator-5554`.
The device was an Android emulator, not a physical phone. Every launch, input,
navigation action, and saved screenshot used the returned device-bound
`agent-device` command. T3 `device_screenshot` also inspected the display.
No alternate UI driver or new binding replaced the stopped binding.

Both ports were free before startup. This worktree started Jellyfin core 12.4.0
on `127.0.0.1:7364` and the HTTP observer on `127.0.0.1:7365`.
The observer forwarded real Jellyfin responses without adding download identity
headers. Synthetic setup generated ordinary Alice and Bob accounts, audio,
an EPUB, and book libraries. No production account or private library was used.
No standalone HTML or Markdown reader behavior was tested or added.

The attempt created its own emulator reverse forward for TCP port 7365.
A reverse forward routes an emulator port to a host port. The app signed in
through `http://127.0.0.1:7365`. The final diagnostic found no reverse forwards.
That route was not recreated after acceptance stopped.

## Observations completed before the stop

| Observation | Actual result | Public screenshot |
| --- | --- | --- |
| Ordinary sign-in and library | Alice signed in and selected Synthetic public. Four visible audio entries showed Not downloaded. | `images/current-main/01-library.png` |
| Book detail | The first visible book opened as a one-file M4B edition, separate from possible matching books. | `images/current-main/02-book-detail.png` |
| Normal download | Download completed at 398,040 / 398,040 bytes, 1 / 1 files. The real Download response was HTTP 200. | `images/current-main/03-completed-download.png` |
| Native playback | The app showed advancing time and Pause. Android reported PLAYING at 24,408 milliseconds with speed 1.0. | `images/current-main/04-playing.png` |
| Pause, short jump, immediate Undo | Explicit Pause stopped the displayed time at 00:49. Forward 30 seconds reached 01:19. Undo returned to 00:49. | `images/current-main/05-jump-undo-history.png` |
| History result restore | Restoring the short jump's result returned to 01:19. A new History restore action appeared above the retained Undo action. | `images/current-main/06-edited-bookmark.png` |
| Bookmark creation and editing | A bookmark at 01:19 saved its synthetic note. Editing changed its title to Runtime bookmark edited. | `images/current-main/06-edited-bookmark.png` |
| Process restart | The first relaunch replaced the app process. Its native owner PID changed from 30592 to 329. The app retained the selected downloaded book without autoplay. | `images/current-main/07-restart-retains-records.png` |
| Persistent position and records | Listening showed 01:19 after restart. Native state was NONE at 79,757 milliseconds. History and the edited bookmark remained visible. | `images/current-main/07-restart-retains-records.png` |
| Previous-place and bookmark restores | History previous-place restore changed 01:19 to 00:49. Bookmark restore changed 00:49 to 01:19 and added a Bookmark restore action. | Live screen references and recorded transition text; no separate screenshot. |
| Bob download isolation | After Alice signed out, Bob signed in. Downloads showed No downloads yet and No retained files. | `images/current-main/08-bob-no-alice-downloads.png` |
| Bob record isolation | Bob had no active selection. History showed No bookmarks yet and No listening actions yet. | `images/current-main/09-bob-no-alice-records.png` |
| Return to Alice | After Bob signed out, Alice signed in again. Her downloaded catalog entry and retained selected position returned. | Live screen references; no separate screenshot. |
| Retained storage with no selected libraries | Deselecting Alice's public library hid the catalog download but retained its 398,040 bytes in the separate storage section. | `images/current-main/10-retained-no-library.png` |
| Retained storage across relaunch | A second app relaunch kept the empty library selection and the same retained source and byte count. | `images/current-main/11-retained-after-restart.png` |
| Retained removal cancellation | Keep files closed the confirmation and preserved the retained source and byte count. | Live screen references; no separate screenshot. |
| Explicit retained removal | Confirmed Remove files cleared retained storage. Downloads showed No downloads yet and No retained files. | `images/current-main/12-retained-removed.png` |

Displayed times use minutes and whole seconds. Native positions use milliseconds
within the selected file. Native NONE after restart did not mean that playback
was active or that a decoder was loaded. It recorded the restored position.
The run did not independently hash the downloaded Android media bytes before
removal. Completion labels and the observed HTTP response are not that check.

The public `current-main-runtime.json` contains the exact artifact identity,
screenshots' SHA-256 hashes, and the allowlisted observer events. The observer
recorded 41 requests between 13:50:34 and 14:03:46 UTC: 32 HTTP 200 responses and
nine HTTP 204 responses. The HTTP 204 responses were one playback start and
eight progress requests. No observer-recorded stop request is claimed.
Three ordinary sign-ins succeeded: Alice, Bob, then Alice.

## Tool errors and the stop

Each failed device action invalidated its references. Recovered actions used
fresh references or an observed exact selector. No retry changed the binding.

| Error | Advice followed and outcome |
| --- | --- |
| `Error (INVALID_ARGS): fill --record-as requires an armed script recording. Start a fresh session with open --save-script, then retry the fill.` | The Hint also requested argument/help inspection. Help and a fresh snapshot showed that stdin entry needed no recording flag. One retry without that flag succeeded in the existing session. No recording session was started. |
| `Error (COMMAND_FAILED): Ref @e13 was not issued by the current ref frame` | Captured the advised fresh interactive snapshot. One retry of the 30-second jump succeeded, and Undo restored the prior position. |
| `Error (COMMAND_FAILED): Field focus was refused` | After Alice signed out, captured a fresh snapshot and used the advised `--debug` retry for the server field. That single retry succeeded. Bob then signed in normally. |
| `Error (COMMAND_FAILED): Selector did not match: label="Library\nTab 1 of 3" role=button` | During library restoration after retained-file removal, Save libraries showed Cannot reach Jellyfin. The requested navigation target did not exist in the still-open library sheet. Captured the advised fresh snapshot. Tapped the observed Dismiss target, which did not dismiss the sheet. One retry of the intended Library action failed with the same error. Acceptance stopped immediately. |

The last failure IDs were `mvzbzfwm-f1777835` and `mvzc02t8-091b50a1`.
Screenshot `images/current-main/13-stopped-library-selection.png` records the
sheet and message. Both loopback services were still listening at the stop.
The emulator's reverse-forward list was empty. Missing host routing explains
the unavailable fixture route; this run did not establish why the route vanished.
No failed HTTP status appeared in the observer's 41 completed request records.
Filtered Flutter/AndroidRuntime error logs were empty.

Two preparatory repository searches also used incorrect paths and returned
`No such file or directory`. Searching the actual file list corrected each.
Neither search launched an app or exercised Bookfin behavior.

## Limits

The stop was not a pass for the remaining matrix. These cases stayed unobserved:

- Grouped slider dragging and immediate Undo.
- Mini-player jumps and Undo, and Pause from the history screen.
- Confirmed bookmark deletion, native notification seeks, and interruptions.
- Offline playback, offline process restart, and reconnect-report reconciliation in this attempt.
- Multi-file playback and chapter transitions in this attempt.
- Replacement-source confirmation, cancellation, and old-record separation on Android.
- Credential-lock setup, locked media controls, and physical-phone behavior.

No Settings page opened, PIN was set, radio was changed, or media-data override
was enabled. No claim of full personal-record sync, hot reload, decoder endurance,
reader compatibility, or user acceptance follows from these observations.

## Build and cleanup

Before the build, load averages were 8.01 / 6.72 / 7.68 and free memory was 47%.
Only one application build ran. Synthetic media generation followed that build.
The build ran through the pinned Nix development shell:

`flutter pub get && bash tool/bookfin build-android`

The normal ARM64 debug APK built in 216.3 seconds. The build reported 15 newer
dependencies outside constraints and Java source/target 8 obsolescence warnings.
No code change or new concrete application concern required a host-suite rerun.
No host tests, analyzer, coverage, mutation testing, web build, or test APK ran.
The evidence audit recomputed all 14 screenshot hashes and found no generated
fixture passwords or account tokens in the public text. The source comparison
against integrated main and `git diff --check` both passed.

Cleanup used system Back only to exit the stuck sheet, then the app's Account
and Sign out controls. Downloads were already empty after confirmed removal.
The app finished signed out with empty input fields and disabled account-only
destinations. Screenshot `images/current-main/14-cleaned-signed-out.png` records
that state. Android reported inactive native state NONE at position zero.
An app-private filename listing showed no files under the native media root,
`files/bookfin-media`. Synthetic history and bookmark preferences were not erased;
sign-out hid them. No shared app-data reset was performed.

Owned Jellyfin PID 84006 accepted authenticated shutdown and exited with status
zero. Owned observer PID 88046 received SIGTERM and its command exited 143.
Neither port 7364 nor 7365 had a listener afterward. The reverse-forward output
contained only its terminating newline, with no forward entries. No route from
another worker was changed, and the research worker's port 7564 was untouched.

The own binding was released with `shutdown: false`; the emulator stayed booted.
The normal current-main APK remained installed. No device session, listener, or
background build from this attempt remained active. Private fixture state, APKs,
and logs remained ignored under `.cache`; none was committed.
No child, PR, ticket closure, or production-server operation occurred.
