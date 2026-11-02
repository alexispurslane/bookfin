# Persistent personal records

Ticket: `boo-6h8w`. Original base: `e8fe9c7`. Verification date: November 2, 2026.

This implementation extends the existing playback owner and account-scoped `ResumeStore`. It adds no second player, position cache, navigation root, sync transport, or retention policy.

## Delivered behavior

- Accepted seeks retain the previous position and the decoder's confirmed result. Each position includes edition ID, source key, source revision, and recorded milliseconds within the source.
- Slider dragging previews a target without seeking. Release records one completed seek from the drag's original position. Another position command invalidates an unfinished drag.
- Short jumps, chapters, native controls, Undo, history restores, and bookmark restores use the same serialized position transition.
- Pause, resume, interruption, stop, and completion edges create history actions. Repeated decoder time samples do not create history rows.
- Undo adds a new action. Dismissing Undo does not remove persistent history. History offers the previous position and the resulting position separately.
- Bookmarks retain stable identifiers, positions, optional titles, and optional notes. The editor retains the position that it showed when opened. Edits preserve the bookmark's identity and position. Delete requires confirmation.
- The existing Listening destination opens account-wide history. Sign-out dismisses the private history route. The shared cream/sepia theme and bundled fonts remain in use.
- Version-1 resumes migrate under the existing storage key. Version 2 adds history and bookmarks without replacing source-relative resumes or playback settings.
- Changed sources fail closed. Their old records remain available. `t8-ld5q` still owns the unresolved replacement-source recovery choice.
- Failed or unreadable account restoration cannot overwrite stored records or start an unsaved recording. Failed writes remain visible, retain a pending account snapshot in the running process, and support retry.

## Meaningful red tests

Tests ran through the pinned Nix development shell before the corresponding behavior was implemented. Interface-only methods initially returned without performing recovery or bookmark work, so recovery tests compiled before their behavioral failures were observed.

| Test phase | Observed failure before the fix |
| --- | --- |
| Persistent core records | Two accepted overlapping jumps produced zero stored jump actions. Pause/resume/interruption history was empty. Restart had no retained seek action. |
| Recovery and bookmarks | Slider release did not preserve the drag's original position. Undo and history restore did not move playback. Bookmark creation produced no retained bookmark. |
| Player controls | Slider updates moved playback before release. History and bookmark controls were absent. |
| Interruption during a pending write | Playback remained playing after an interruption because seek handling suppressed samples until the write finished. |
| Old-account command failure | A decoder error from the previous account appeared in the next account. |
| Unreadable action | An unknown stored action kind escaped as an argument error instead of preserving the unreadable account data behind a restore guard. |
| Confirmed seek result | The decoder confirmed 13,000 milliseconds in the second source, but playback retained the requested 15,000 milliseconds. |
| Opening after a failed account read | Playback acquired a position and attempted to record a resume despite failed restoration. The state assertion also exposed this invalid session. |

The initial persistent-core test command was:

```sh
nix develop --command flutter test test/playback/history_test.dart
```

Focused regression commands included:

```sh
nix develop --command flutter test test/playback/screen_test.dart
nix develop --command flutter test test/playback/history_test.dart --plain-name 'history retains the confirmed decoder result'
nix develop --command flutter test test/playback/history_test.dart --plain-name 'opening a recording after a failed account read'
```

## Final verification

The commands below ran sequentially, with one build or test command active at a time. No emulator was opened or controlled.

| Command | Final result |
| --- | --- |
| `nix develop --command flutter test --reporter expanded` | All 227 tests passed. This includes the original native zero-position, source-identity, and interruption regressions. |
| `nix develop --command flutter analyze` | No issues found. |
| `nix develop --command bash test/sdk_link_test.sh` | Passed. This is a temporary-directory test of additive SDK discovery links, not a change to the live device host. |
| `nix develop --command bash tool/bookfin build-android` | Built `build/app/outputs/flutter-apk/app-debug.apk` for Android ARM64. |
| `nix develop --command bash tool/bookfin build-web` | Built the JavaScript web application in `build/web`. |
| `git diff --check` | Passed. |

The final aggregate command was:

```sh
nix develop --command bash -c 'dart format lib/playback/playback.dart test/playback/history_test.dart && flutter test --reporter expanded && flutter analyze && bash test/sdk_link_test.sh && bash tool/bookfin build-android && bash tool/bookfin build-web'
```

All other changed Dart files were also formatted through the Nix shell before the final aggregate run.

The first Android build reported Java 8 source/target deprecation warnings from native dependencies. The incremental final build succeeded. The web build reported existing package limitations during its WebAssembly dry run and a Cupertino icon-font warning. The JavaScript build succeeded. No dependency or toolchain upgrades were introduced to address those unrelated warnings.

## Behavioral coverage within the host tests

`test/playback/history_test.dart` exercises grouped slider seeks, overlapping jumps and recovery commands, pause/resume/interruption edges, native controls, confirmed decoder positions, failed restores, missing local files, changed source revisions, and cross-edition restores with Undo. It also exercises bookmark edits and deletion, ordinary restarts, actual local-store migration, account restoration, account switching, unreadable records, pending-write interruptions, and failed-write retry.

`test/playback/screen_test.dart` exercises a slider preview followed by one committed seek, immediate Undo, bookmark creation, bookmark editing, bookmark restore, and confirmed deletion. `test/playback/root_history_test.dart` exercises the existing Listening navigation and private-route dismissal on sign-out. Test fixtures use in-memory or mocked local storage and synthetic local-file locations. No production Jellyfin requests or secrets were used.

`Playback.checkInvariants` remains available in every build. It checks selection/account agreement, valid source-relative positions, unique record identifiers, retained Undo actions, valid unfinished slider origins, and pending snapshots for failed writes. Internal transition assertions remain debug-only.

## Limits and parent follow-up

Android compilation is not Android runtime acceptance. The parallel reader proof owns the emulator during this task. The parent must observe dragging, Undo, notification seeks, interruption handling, bookmark editing, and restart recovery on the integrated Android build. No phone access, hot reload, APK installation, or new Android runtime observation is claimed here.

Host restarts recreate the playback owner and read persisted records. They do not simulate a power loss or terminate the Android process during a pending disk write. A failed write cannot become durable without a successful retry. The interface tells the user to keep Bookfin open and retry. Pending in-memory snapshots cannot survive process death.

The web build retains the existing platform restriction: it does not provide the production Android decoder or media session. No browser interaction was requested or performed.

History has no pruning or expiry. Full personal-record synchronization, merge policy, remote deletion semantics, retention policy, and replacement-source reconciliation remain outside this ticket. No coverage or mutation jobs ran. Independent review, integration, runtime acceptance, and later hardening remain with the parent. The ticket stays `in_progress`.

## Parent review corrections

The review of `14ab8c5` found five defects. Seven new regression cases first failed for the intended behavior. They cover a failed cross-edition restore, recovery through Play or a seek, a slider gesture behind a pending write, explicit Pause during interruption, Stop while paused, and the foreground controls.

A cross-edition restore now waits for a confirmed decoder position before it changes selection and records the action. A failed restore retains the old selection and Undo. Samples from the failed decoder load cannot change that retained position. The next Play or seek reloads the retained recording before it proceeds.

The slider captures its origin when the gesture starts. A pending disk write cannot move that origin forward. Account changes and intervening position commands still invalidate the gesture. Explicit Pause and Stop record their command effects once, including when an interruption already paused audio.

The full player and mini-player share one Undo control. History keeps the mini-player visible, so the user can pause or undo a restore without leaving History.

Parent verification through Nix: all 234 application tests pass and analysis reports no issues. The initial new history widget test needed its storage setup inside the test runner's asynchronous helper. After that correction, it failed because History had no Pause control. That setup failure is not counted as behavior evidence. Android runtime acceptance remains outstanding. No device, production-server, coverage, or mutation work ran in this correction.
