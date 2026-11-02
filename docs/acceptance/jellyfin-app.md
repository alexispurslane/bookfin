# Real Jellyfin application acceptance

Ticket: `boo-2cgp`, still in progress.
Baseline: `ae6be0e84539515b5c77cbb419b2f0a67c923cfd`.
Execution date: November 2, 2026.

A new checkout-local fixture runs the pinned official macOS ARM64 Jellyfin
archive. Its runtime reports 12.4.0. It binds only `127.0.0.1:7364`.
No production account, shared service, or Enhanced plugin is used.
Fixture setup reuses research utilities. Application behavior does not.

Reproduction: `tool/acceptance/README.md`.
Observed requests: `tool/acceptance/evidence/app-http.json`.
Evidence contains synthetic identifiers, hashes, and response metadata.
It omits credentials, request bodies, and absolute media paths.

An HTTP ETag identifies a server response's file contents.
A strong HTTP ETag identifies one exact byte representation.
A source revision is the app's observed version of a media source.
SHA-256 is a hash that summarizes a file's bytes.

## Executed application behavior

The tests call production `JellyfinClient`, `CatalogController`, `buildBooks`,
explicit correction operations, and `LocalDownloads`.
The HTTP observer returns real responses unchanged.
No playback implementation or progress report is added.

| Check | Executed outcome | Boundary |
| --- | --- | --- |
| Ordinary accounts | Alice loads six book sources. Bob loads five and cannot see the hidden source. | Both fixture accounts explicitly lack administrator status. |
| Library selection | The server offers accessible music. The app excludes it and rejects its library identifier. | Only selected book libraries supply the published catalog. |
| Matching titles and folders | Five public sources remain five books until explicit corrections. | No silent title, folder, or provider pairing occurs. |
| Explicit corrections | Confirmed links produce one book with three editions: a three-file recording, a separate recording, and an ebook. | Combining audio rejects the ebook. |
| File order | The first disc's tracks 1 and 2 precede the second disc's track 1. A confirmed reverse order survives refresh and restoration. | Two embedded chapters remain separate from file boundaries. |
| Exact bytes | Three audio files and the EPUB match independently seeded bytes and SHA-256 hashes. | This is production host filesystem behavior, not Android UI or playback. |
| Account storage | Bob cannot reuse Alice's local file. His download of the same ebook gets a different account path. | Returning to Alice restores her original local file. |
| Download-owner restart | A new download owner verifies completed files without HTTP. | This is an object restart, not an Android process restart. |
| Interruption | A nonzero saved prefix survives owner restart. Retrying completes exact bytes with HTTP 200. | Jellyfin omits a strong HTTP ETag, so the app safely starts over. |
| Download permission | Live revocation defeats a stale allowed session before media HTTP. A raw Download returns 403. | Restoring permission allows exact ebook acquisition. No File fallback occurs. |
| Inaccessible items | The app receives item 404 and publishes no bytes. Raw hidden and missing Downloads return 404. | Cross-user queries return 403. Unauthenticated Download returns 401. |
| Library revocation | Cached hidden content disappears and stays hidden after controller restoration. | Restored permission and an explicit selection recover it. |
| Account identity | Real server and current-user responses reject mismatched saved server and user identifiers. | This intentionally mismatches saved sessions. It does not replace a server installation. |
| Source identity | Replacing synthetic bytes changes the real source revision. Stale acquisition fails before Download. | Refreshed bytes get separate storage. Removal deletes owned old revisions too. |

The test-only disk stores replace native credential and preference plugins.
They exercise session serialization and account-scoped catalog restoration through
the production controller. They do not prove Android secure-storage behavior.
No host keychain, production credential, device, browser, or preview is accessed.

## Meaningful failures and corrections

| Defect | Red result before correction | Correction |
| --- | --- | --- |
| Catalog authentication | Seven live checks fail on authenticated catalog 401 after successful sign-in. | Include the token in modern Authorization. Retain the older token header. |
| Download authentication | After catalog authentication works, real media still fails with authorization denial. | Include the token in download Authorization too. |
| Original ebooks | The real EPUB fails as an unsupported source after authentication works. | Represent a Book without MediaSources as its unnamed original source, matching the catalog model. |

The real Book has `CanDownload` and a nonempty item revision, but no
`MediaSources` array. The correction does not grant access by type alone.
Current-user permission, item permission, source identity, revision, length, and
completed-byte checks remain enforced. Audio without source metadata stays rejected.

The server always returns `EnableContentDownloading`.
Missing permission therefore remains an explicitly synthetic production-download
test. It removes that field and proves that no media request starts.
Strong-ETag range recovery remains separately proven by synthetic transfer tests.

## Verification

All commands run sequentially through the pinned Nix shells.
The profiles below are created from the repository's existing flakes.

| Command | Result |
| --- | --- |
| `nix develop .cache/dev-shell --command flutter test --no-pub --concurrency=1 --reporter expanded` | 154 application tests pass. |
| `nix develop .cache/dev-shell --command flutter test --no-pub --concurrency=1 --reporter expanded --dart-define=BOOKFIN_APP_ACCEPTANCE=true tool/acceptance/jellyfin_app_test.dart` | Nine real-server application checks pass. Range reuse is not claimed. |
| `nix develop .cache/sync-shell --command python3 -m unittest discover -s tool/research/sync -v` | 40 research tests pass. These do not count as application HTTP acceptance. |
| `nix develop .cache/dev-shell --command flutter test --no-pub --concurrency=1 --reporter expanded tool/research/jellyfin/probe_test.dart tool/research/jellyfin/whole_set_fixture_test.dart` | 32 earlier probe and storage-model tests pass. |
| `nix develop .cache/dev-shell --command bash test/sdk_link_test.sh` | Additive SDK-link checks pass, entirely inside temporary directories. |
| `nix develop .cache/dev-shell --command flutter analyze --no-pub` | No issues. |
| `nix develop .cache/dev-shell --command dart format --output none --set-exit-if-changed lib/catalog/jellyfin.dart lib/downloads/local_downloads.dart test/catalog/jellyfin_test.dart test/downloads/transfer_test.dart tool/acceptance/fixture_support.dart tool/acceptance/jellyfin_app_test.dart` | Six changed Dart files are formatted. |
| `git diff --check` | Passes. |

The first attempted probe command used standalone Dart instead of the Flutter
test runner. It could not load `dart:ui`. The correct command above passes.
The first focused ebook regression also needed a larger test storage allowance
because the real Book representation omits its file length. That fixture issue
is separate from the meaningful real-server unsupported-source failure.
Repeated live runs also exposed fixture cleanup that restored bytes but let a
scan replace the shared synthetic title. Cleanup now restores and checks that
metadata too. This fixture failure did not require an application correction.

## Outstanding release gates

`boo-2cgp` is not complete and must not be closed from these checks alone.

1. Exercise the integrated corrected-head Android catalog and download screens.
   Include interruption, cancellation, immediate cancel/remove after restoration,
   and an early-file failure while later files remain active.
2. Prove ordinary-account secure-storage restoration across an Android process
   restart, account switching, and sign-out in the installed app.
3. Resolve `t7-bzzg`, the real-server prefix-resume gate. Responses return
   Last-Modified but no strong HTTP ETag. Do not weaken replacement safety silently.
4. Retain `boo-p58t` for separate personal-record storage and sync acceptance.
   This suite emits no progress writes and proves no sync implementation.

The Android device remains reserved for parallel playback work.
No device, browser, coverage, or mutation-testing operation runs here.

## Fixture shutdown

The authenticated fixture shutdown completed and the server process exited.
`lsof -nP -iTCP:7364 -sTCP:LISTEN` then reported no listener.
The restartable fixture remains only in this checkout's ignored runtime directory.
The runtime directory is mode 0700. Account, password, and result files are mode 0600.
No shared service or SDK installation was changed.


## Parent evidence-publication correction

The publisher now deletes stale observations and runs the live Flutter acceptance suite itself. Publication requires that same process to exit successfully, including all cleanup. The ninth check records success only after source metadata restoration. A regression reproduced false publication before the fix and now proves a failed runner leaves previous public evidence unchanged.

Parent verification: the corrected publisher executed all nine checks successfully against the retained disposable Jellyfin fixture and regenerated app-http.json; 154 application tests pass, the publication regression passes, and scoped Dart analysis is clean. The server exited and port7364 has no listener. No Android, production-server, or credential-storage acceptance is added by this run.

## Integrated Android follow-up

The November 2 follow-up started at main `d9bc3a6` with a new checkout-local Jellyfin fixture.
See `docs/evidence/playback/integrated-android.md` for the runtime observations and their limits.
It observed production ordinary-user sign-in, native credential restoration after process restart, account isolation, explicit ebook pairing, and ordered audio acquisition.
It also observed restored cancellation/removal, cancellation after an early-file failure, exact downloaded bytes, and downloaded offline playback.
Real Jellyfin accepted native-player start, progress, and stop reports with HTTP 204.
The follow-up found a concrete native position-sampling defect, tracked separately in `t0-dqxp`.

The first two outstanding gates now have runtime evidence for parent acceptance.
They are not ticket-closure decisions. The strong-validator gate `t7-bzzg` remains open.
The discrete interrupted native Pause case remains unobserved in `t0-60ea`.
No production-server, physical-phone, credential-locked-screen, or full personal-record-sync acceptance is added.
