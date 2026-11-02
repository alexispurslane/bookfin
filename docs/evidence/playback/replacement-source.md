# Confirmed fresh start for changed audio

Ticket: `t8-ld5q`. Date: November 2, 2026.
Base: `756ae5fcf77f8d1f9d18124311fedbc085c7605b`.
Prepared branch: `t3/confirmed-audio-replacement`.

## Delivered behavior

The approved recovery choice is implemented through the existing `Playback`
owner and account-scoped `ResumeStore`. There is no second player, record store,
sync transport, or recovery framework.

- Changed audio offers an explicit fresh start. The dialog explains that the
  replacement starts at the beginning and keeps the original position, history,
  and bookmarks separately. Cancel does not start audio or change those records.
- A replacement position becomes selected only after a successful local decoder
  load. Failed loads keep the offer and original records. Old-account offers and
  canceled or obsolete offers cannot commit after a delayed load.
- Aborting a replacement load keeps a prior recording's position and Undo. It
  does not falsely report that the paused decoder is playing. Play reloads that
  prior recording before continuing.
- Each known recording retains its own resume within the existing edition.
  Changing source revisions cannot overwrite an original resume, even when the
  replacement begins in an unchanged file. Correcting file order does not make
  the same files a different recording. The decoder still follows the corrected
  order.
- History and bookmark positions are not rewritten. Existing source-revision
  checks refuse incompatible restores. Returning to the original recording can
  restore its saved resume; returning to the replacement restores its own resume.
- A fresh start cannot bypass missing source revisions or media-source IDs.
  The existing complete-local-download requirement also remains in force.
- Failed writes retain account-specific pending snapshots for retry. New resume
  lists are copied into each write snapshot; later playback does not change an
  already queued snapshot.

The local payload is version 3 under the unchanged
`bookfin.playback.v1.<AccountScope.key>` storage key. Version-1 and version-2
resumes migrate into lists without changing their original source positions.
Known recordings also retain their source keys and revisions. Legacy records
keep their source-relative identity until a matching recording loads. Migration
does not guess a replacement revision. Existing history, bookmarks, speed, jump
settings, and offline-pending flags are retained. Older application versions that
do not support version 3 cannot read the new payload.

## Red-green evidence

The 18 new behavior cases are in `test/playback/replacement_test.dart`.
Initial interface-only stubs allowed compiled behavior failures before the
implementation. Later cases exposed retention and canceled-load defects before
their fixes. The tests assert playback, restoration, persistence, and user
controls rather than private collection layouts or schema constants.

| Stage | Meaningful observed failure |
| --- | --- |
| Replacement offer | Expected a pending offer; actual value was null. |
| Confirmed fresh start | Expected the replacement edition; actual selection was null. |
| Retained original | After replacement playback, an original resume expected at 18,000 milliseconds was missing or reset to zero. |
| Pending-write preservation | Returning to the original after a blocked write expected 18,000 milliseconds; actual value was zero. |
| Confirmation controls | Tapping Start replacement failed because the player contained no matching control. |
| Stale or canceled load | Expected no selected position; an obsolete replacement position was selected. |
| Unknown source revision | Expected no selected position; fresh start accepted unidentified audio. |
| File-order correction | Expected the replacement source revision and its saved position; actual selection was null. |
| Aborted load with another recording selected | Expected playback to be paused; the owner still reported playing. |

Other cases exercise cancellation without writes, failed decoder loads, account
changes before confirmation and during load, replacement bookmark restoration,
unchanged first files, and both recordings across owner recreation. Version-1
and version-2 cases use `LocalResumeStore` with the preferences test backend;
they serialize both recordings, recreate the owner, and restore both resumes.
They also check settings and retained version-2 history and bookmarks. Failed
write cases switch accounts, restore from the pending snapshot, and retry.

One early unknown-source test omitted a required constructor argument. That
compile failure is not red evidence; the corrected test then failed because it
accepted an unidentified replacement. The widget test initially mixed the test
runner's simulated clock with real asynchronous playback commands. Its two
stalled runs were interrupted. Opening and completing its dialog in the test
runner's real asynchronous helper resolved that test-harness issue. These runs
are not product failure or passing-check evidence.

## Final verification

All commands ran sequentially through the pinned Nix development shell. The
shell used the existing project dependency caches. No device or external server
fixture was opened, started, or changed.

| Check | Result |
| --- | --- |
| `dart format --output=none --set-exit-if-changed` on the four changed Dart files | Pass; zero changes. |
| `flutter test test/playback --reporter expanded` | All 101 playback tests pass. |
| `bash test/sdk_link_test.sh` | Pass; additive SDK-link behavior, including refusal cases. No host SDK changes. |
| `flutter test --reporter expanded` | All 289 app tests pass. |
| `flutter analyze` | No issues found. |
| `flutter build apk --debug --target-platform android-arm64` | Pass; normal `lib/main.dart` Android ARM64 debug APK. |
| `flutter build web --release` | Pass; JavaScript release application. |
| `git diff --check` | Pass. |

The Android artifact is `build/app/outputs/flutter-apk/app-debug.apk`. Its SHA256
is `b4156460444c6fa6f66226a9ed156cbaebe2297f1bf244f6e647ee5b4548c689`.
The web artifact is `build/web/main.dart.js`. Its SHA256 is
`17ae286a860c56a8966404ef35e1c71eca8326b2ef1656e328d379ed5b3bcd4d`.

The first Android build reported existing native-dependency Java 8 source and
target deprecation warnings. The final incremental Android build succeeded.
The web build reported dependency limitations during its WebAssembly dry run
and the existing Cupertino icon-font warning. JavaScript compilation succeeded;
WebAssembly support is not claimed. No dependencies or toolchains were changed.

## Integration and runtime limits

This is a separate-worktree implementation from the stated base, not an
integrated-main or Android runtime acceptance result. Android acceptance is
running separately on the integrated base. The orchestrator must integrate and
review this commit before claiming replacement behavior on that base or device.
This work used no emulator, phone, browser, live Jellyfin requests, credentials,
external fixture process, or APK installation.

Host restart tests recreate the playback owner and read serialized records. They
do not kill an Android process or prove survival of a power loss during a write.
Failed-write snapshots remain in memory until retry succeeds; they cannot
survive process death before a successful save. The existing save warning and
retry controls remain in use.

No child agents, PR, coverage, mutation, ticket closure, or shared-checkout reset
were used. No custom background process, device binding, port forward, or
temporary device setting was created. Build outputs and local diagnostic logs
remain ignored or outside the checkout. Shared dependency caches remain in
place. The orchestrator owns integration, runtime acceptance, hardening, and
ticket closure.
