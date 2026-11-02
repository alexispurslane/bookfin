# Remaining listening and download acceptance

Date: November 2, 2026. All times here use UTC.
Source: `ac6a247a654829d5204437a203b2b61c3ed15234`, the current-main base supplied to this worker.
Tickets: `boo-6h8w`, `t9-k4lf`, `t8-ld5q`, and route follow-up `td-7yxu`, under epic `boo-fs0n`.

Result: the requested priority interactions passed on Android after explicit parent device handoff.
No production code changed. Four additional host regressions also pass.
This report does not accept replacement-recording behavior, notifications, interruptions, sync, or the separate EPUB branch.
The parent owns integration, user acceptance, hardening, and ticket closure.

## Candidate and ownership

An APK is an Android installation file. SHA-256 identifies its bytes.
The normal `lib/main.dart` ARM64 debug APK built through the project Nix shell in 271.2 seconds.
Its size was 93,551,630 bytes.
The built APK and the installed APK read back from Android both had this SHA-256:

`6ecf12063e68e73a0642563be1cd269fde49f1609b49284a7c84cf39baf38f42`

No leftover EPUB APK served as this candidate. Application, Android, dependency-lock, and Nix sources remained unchanged from the source commit.
Only tests, evidence, and ticket notes changed.

Initially the EPUB worker owned `local` / `emulator-5554`. This worker performed host checks only.
The parent then explicitly transferred exclusive device ownership after the EPUB worker completed cleanup.
This worker opened its own binding, `t3-c842536e0912f963d18c4a0c`, using `device_open` with those identifiers.
Every launch, field entry, gesture, navigation action, and screenshot used the returned bound `agent-device` command.
T3 `device_screenshot` also inspected the screen.
Normal tools performed builds, installation, APK readback, private-file test setup, diagnostic reads, and the owned port forward.
No adb, simctl, or ssh UI action substituted for the bound command.

Both ports were free before startup. This checkout started Jellyfin core 12.4.0 on `127.0.0.1:7364` and its observer on `127.0.0.1:7365`.
The ordinary synthetic account signed in through `http://127.0.0.1:7365`.
A reverse forward routes an emulator port to a host port. This worker created only its own port-7365 reverse forward.
No production account, private library, other fixture, or previous worker binding was used.

## Acceptance matrix

Previously observed means the earlier run in `current-main-android.md`, whose source was `261d50eb48dbe78288d44419d692e27268430a78`.
New host verification means Flutter tests on this computer. It does not prove Android behavior.
New Android observation means this candidate and this worker's actual emulator actions.

| Requested behavior | Previously observed | Newly host-verified | New Android observation or remaining limit |
| --- | --- | --- | --- |
| Sign-in, library, complete download, native playback | Yes | Existing focused suite passes | Repeated with this APK. Screenshots 01–04. |
| Full-player short jump and Undo | Yes | Existing history and screen tests pass | This run targets the previously missing mini-player and slider cases instead. |
| History previous-place/result restore | Yes | Existing history tests pass | Previous evidence remains the Android evidence. No new restore interaction claimed. |
| Pause from History | No | Existing History mini-player test passes | Pause changed the control to Play and added one Paused record at 39,977 milliseconds. Android reported PAUSED. Screenshot 05. |
| Mini-player forward jump and Undo | No | Existing mini-player jump/Undo test passes | History's mini-player moved 39,977 → 69,977 milliseconds. Undo returned to 39,977 and retained the jump record. Screenshots 06–07. |
| Grouped slider gesture and Undo | No | Existing slider, overlapping-gesture, and gesture-origin tests pass | One continuous 1,500-millisecond pan moved 39,977 → 126,957 milliseconds. Undo returned to 39,977. Exactly one Seek record persisted. Screenshots 08–10. |
| Bookmark create, edit, restore | Yes | Existing bookmark tests pass | A new bookmark was created for deletion checks. No new edit/restore runtime claim. |
| Cancel bookmark deletion | No | New UI regression checks identity, title, note, and restore after owner recreation | Cancel preserved the bookmark, note, and 00:39 position. A process relaunch retained them. Screenshots 11–13. |
| Confirm bookmark deletion | No | New UI regression checks deletion across owner recreation while another bookmark and history survive | Delete removed the bookmark. After relaunch, No bookmarks yet appeared while Seek and Undo history remained. Screenshots 14–15. |
| Account isolation | Yes | Existing account/server isolation tests pass | Not repeated with another account in this run. |
| Unavailable saved files | No | Existing rejected-copy UI test and corrupt-copy tests pass. New removal test handles a file disappearing during confirmation | A deliberately corrupted local copy stayed visible as 398,673 saved bytes unavailable for playback. Listening refused it. Screenshot 16. Actual file disappearance during confirmation remains host-only. |
| Retry → Cancel → restart | No | Existing rejected-copy UI regression passes through retry, cancellation, owner recreation, and removal | An injected failure exposed Retry. Retry received 4,096 bytes. Cancel stopped it. Relaunch retained both the unavailable copy and canceled prefix, without another download request. Screenshots 17–20. |
| Retained visibility after catalog loss/restart | Yes | Existing inventory, isolation, and restoration tests pass | Deselecting the library moved 402,769 bytes into Retained storage. Relaunch preserved them. Screenshots 21–22. |
| Keep/Remove retained files | Yes | New regression checks removal through owner recreation and reselection without another transfer | Keep download and Keep files preserved the copies. Confirmed Remove files deleted both copies. Relaunch and library reselection still showed no download or retained files. Screenshots 23–26. |
| Replacement confirmation/cancel and original-record separation | No | Existing 21 replacement tests pass | Still pending on Android under `t8-ld5q`. No Jellyfin source bytes changed in this run. |

All screenshot paths are under `images/remaining-acceptance/`.
`remaining-acceptance-runtime.json` records the filenames and hashes, exact positions, process replacements, and allowlisted observer events.
Displayed positions use minutes and whole seconds. Stored and native positions use milliseconds within the single audio file.

## Saved-file fault and cancellation

This was deliberate test setup, not a discovered corruption defect.
The complete downloaded copy first matched the original synthetic Jellyfin source by SHA-256:

`929bbed62214ee77c9faec26db981f6bdaa60351ac77604e5b936ceb0da37314`

Only byte offset 200,000 of that owned app-private copy changed. Its length remained 398,673 bytes.
The resulting SHA-256 was `a9c155b65382174a6a60a8066173a4c8b1ef0f46098a9e50a32b662173f284b1`.
The original Jellyfin media remained unchanged. No preference, resume, history, bookmark, or manifest was fabricated to make the UI pass.

After relaunch, Bookfin rejected the copy for playback but kept its bytes visible and removable.
The observer then injected one HTTP 503 for this synthetic item's Download route.
After the failure appeared, the observer forwarded real download bytes with a two-second delay between 4,096-byte chunks.
The user-facing Retry action started receipt. Cancel stopped receipt after 4,096 bytes.
The saved manifest recorded `requested: false`. The fault controls returned to `{}` before the next relaunch.

After that relaunch, Downloads still showed Retry, Remove, 4,096 partial bytes, and 398,673 unavailable saved bytes.
No automatic download followed cancellation, relaunch, library deselection, or reselection.
Outside the selected catalog, Retained storage counted both files: 398,673 + 4,096 = 402,769 bytes.
The removal confirmation named that byte count. Keep files preserved it. Remove files cleared it.
Another relaunch and library reselection did not restore those files or start a transfer.

The observer recorded 58 response-header records and one follow-up connection-interrupted record.
Header statuses were 48 HTTP 200, nine HTTP 204, and one deliberately injected HTTP 503.
There were exactly three Download response-header records: original completion, injected failure, and canceled retry.
An HTTP 200 header alone is not proof that the response body completed. The canceled retry did not complete.

## Process replacements and route checks

Each relaunch used this binding's `open dev.bookfin.bookfin --relaunch`.
The process identifier changed each time. The owned reverse forward remained present before and after every relaunch.
Library reselection also succeeded through the real fixture after removal. Earlier route loss was not reproduced or explained.

| Check | Before time and process | After time and process | Purpose |
| --- | --- | --- | --- |
| 1 | 18:36:08, 16636 | 18:36:16, 19040 | Canceled bookmark deletion persists |
| 2 | 18:38:23, 19040 | 18:38:30, 19648 | Confirmed deletion persists and corrupted download is rejected |
| 3 | 18:40:16, 19648 | 18:40:23, 20173 | Canceled retry does not restart |
| 4 | 18:41:43, 20173 | 18:41:50, 20625 | Retained copies survive catalog loss and restart |
| 5 | 18:42:54, 20625 | 18:43:01, 21004 | Confirmed removal persists |

The final account-scoped history contained the same six action identifiers as after slider Undo.
Their kinds were Resume, Pause, Short jump, Undo, Seek, and Undo. Bookmark cancellation/deletion did not erase them.
The final account had no bookmarks.

## Host verification

Commands ran through the pinned Nix development shell.
The focused set is `test/playback/{history,screen,root_history,replacement,remaining_acceptance}_test.dart` plus `test/downloads/{retained,screen,transfer}_test.dart`.
The baseline omitted the new `remaining_acceptance_test.dart` file.

| Exact command after `nix develop --command` | Result |
| --- | --- |
| `bash -c 'flutter pub get && bash tool/bookfin build-android'` | Normal ARM64 debug APK built. Installed APK hash matched. |
| `flutter test test/playback/history_test.dart test/playback/screen_test.dart test/playback/root_history_test.dart test/playback/replacement_test.dart test/downloads/retained_test.dart test/downloads/screen_test.dart test/downloads/transfer_test.dart --reporter expanded` | Baseline: 150 tests pass. |
| `flutter test test/playback/history_test.dart test/playback/screen_test.dart test/playback/root_history_test.dart test/playback/replacement_test.dart test/playback/remaining_acceptance_test.dart test/downloads/retained_test.dart test/downloads/screen_test.dart test/downloads/transfer_test.dart --reporter expanded` | Final focused run: 154 tests pass. |
| `flutter test --reporter expanded` | All 310 application tests pass. |
| `flutter analyze` | No issues found. |
| `dart format --output=none --set-exit-if-changed test/playback/remaining_acceptance_test.dart` | Zero formatting changes. |
| `bash -c 'bash test/sdk_link_test.sh && bash test/sdk_platform_test.sh && bash test/darwin_native_tools_test.sh'` | All shell checks pass, including deliberate rejection/signature-failure cases. |

The four added regressions catch deletion on Cancel, deletion of unrelated records, removal that reappears after recreation, and failed removal of an already-missing file.
They test existing behavior. No production fix or artificial failing implementation was introduced.
Early new-widget runs encountered test setup errors: a lazily built History control and an offscreen deletion button/title.
The tests now scroll to their real controls and inspect durable outcomes. Those setup failures are not meaningful red behavior evidence or product defects.

Build output included 19 dependencies newer than the allowed constraints and Java source/target 8 obsolescence warnings.
No dependency or toolchain update was attempted. No coverage or mutation campaign ran.

## Reproduction and remaining handoff

Use only this checkout's disposable fixture and private synthetic account files.
Do not seed an existing fixture again. `tool/acceptance/README.md` describes first setup and safe restart.
On a fresh checkout, after exclusive device handoff and checking both ports are free, start the core fixture:

```sh
umask 077
nix develop ./tool/research/sync --profile .cache/sync-shell --command bash -c \
  'export BOOKFIN_SYNC_CORE_ONLY=1; exec python3 tool/research/sync/fixture.py serve'
```

In a second terminal, prepare that fixture once, then start its observer:

```sh
nix develop .cache/sync-shell --command python3 tool/research/sync/fixture.py wait
nix develop .cache/sync-shell --command python3 tool/research/sync/fixture.py seed
nix develop .cache/sync-shell --command python3 tool/acceptance/jellyfin_fixture.py
nix develop .cache/sync-shell --command python3 tool/acceptance/android_proxy.py
```

Build the named candidate, install it, and read back its hash. Obtain a new `device_open` binding before any UI actions.
Use the new bound command and fresh references. The released command in this report is not reusable.
Create only the new worker's port-7365 reverse forward. Check its presence before and after every relaunch.
Sign in as this fixture's ordinary account, select Synthetic public, download one M4B, and observe playback before fault setup.
For the saved-file scenario, first match the owned downloaded file to the original fixture hash.
Change only that owned app-private copy. Keep the source media and manifest unchanged.
Set the observer controls for that fixture's item identifier, not the item identifier recorded here.
Perform the sequence in the matrix. Remove the owned files through the app, reset fault controls, sign out, and stop owned resources.

Replacement confirmation/cancel and original-record separation still need a separate Android sequence under `t8-ld5q`.
The original Jellyfin source was never replaced here, so this report cannot prove those behaviors.
Native notification/lockscreen seeks, interruptions, physical-phone behavior, and a file disappearing while its removal dialog is open remain unobserved here.
The continuous forward slider pan does not prove every backward, overlapping, or multi-file Android gesture. Those edge cases have host tests only.
Existing account-isolation, history-restore, bookmark-edit/restore, and other Android observations remain attributed to the earlier report, not rerun here.

## Tool failure and cleanup

The first server-field fill returned `Error (COMMAND_FAILED): Field focus was refused`.
Its advice was `Retry with --debug and inspect diagnostics log for details.` Diagnostic ID: `mvzlcq8y-82c590e3`.
A fresh snapshot showed that field focused. The single advised `--debug` retry succeeded and its diagnostics were inspected.
No repeated device failure occurred, and no fallback UI mechanism was used.
An early host edit command found no `apply_patch` executable on PATH. No file edit happened in that failed command.
Subsequent edits used the bundled Codex patch handler. This did not start another agent or alter global tools.

Cleanup restored Synthetic public selection, then signed out through the app.
Screenshot 27 records empty sign-in fields and disabled account-only destinations.
The native media state was inactive NONE at position zero. The app-private media root contained no files.
The owned corrupted complete copy, partial copy, and their manifest were removed through confirmed retained removal.
No shared app-data reset occurred. Other synthetic-account preferences were not edited or erased.
Own history remains stored but hidden by sign-out. The deleted own bookmark remains absent.

No Android Settings page, text scale, PIN, radio, media override, or appearance configuration changed in this run.
The installed current-main APK remains. Own reverse forward was removed, and its final list was empty.
Jellyfin PID 52965 exited zero after authenticated fixture shutdown. Observer PID 54666 exited 143 after SIGTERM.
Both ports had no listener after cleanup. The own Gradle daemon stopped, and no owned build, test, fixture, or observer process remained.
The binding was released with `shutdown: false`. The emulator stayed booted and is available for the parent's next handoff.
Private credentials, fixture state, raw preferences, media backups, APKs, and build logs remain ignored under `.cache`.
No child, PR, production-server operation, ticket closure, or hardening claim follows from this run.
