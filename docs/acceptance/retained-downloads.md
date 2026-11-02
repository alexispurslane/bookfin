# Retained download storage implementation

Ticket: t9-k4lf. Original base: `72996e4fe51d43639a08127ad3fdf0f1a74ef2f3`.

This implementation extends the existing download owner and Downloads page. The ticket remains in progress for independent parent review, integration, and runtime acceptance.

## Behavior

Retained storage means regular local media files whose saved source revision is absent from the current account's active catalog. The section reports stored bytes separately from current edition availability. Inventory uses existing private directories and records, not a second download index.

Confirmed removal applies to one identified retained source revision. The owner rechecks account, catalog membership, saved identity, and path containment. Unknown identity records disable removal. Unknown unrelated files, symbolic links, other accounts, and current source revisions are not cleanup targets.

Downloads remains reachable with no selected libraries. Reselection verifies existing files and does not redownload a valid completed copy. Inventory does not resume an unreachable source or change media authorization. An in-flight transfer stops before retained removal can run.

## Red-green evidence

Tests use temporary real directories, real download storage, and disposable loopback HTTP fixtures. No production Jellyfin request or credential was used.

| Stage | Meaningful observed failure | Result after implementation |
| --- | --- | --- |
| Initial retained behavior tests | Thirteen tests failed because inventory was empty despite retained bytes. The first assertion expected one retained source and received none. | Inventory, explicit removal, identity checks, and isolation passed. |
| Separate storage UI | Two widget tests failed because the retained section and confirmation action were absent. | The section and confirmed removal passed, including keeping files. |
| Account restoration | An account switch exposed a premature inventory read before the new private account directory existed. | The new restoration future is installed before any listener notification, including network-policy reset. |
| Empty library selection | The library selector hid Downloads even when its navigation destination was selected. | Downloads takes precedence over the selector for a signed-in account. |
| Private storage failure | A failed inventory future escaped before the next widget frame attached its error handler. | The view handles early errors and renders the storage failure without old rows. |

The initial test compilation typo was corrected before recording meaningful red results. Widget-test waits were corrected to wait for real filesystem futures rather than arbitrary delays. These test-harness corrections are not product red-green evidence.

Boundary tests also cover account switches during reads and restoration, revision replacement, revalidation after metadata changes, missing and oversized records, linked records, linked account and source directories, linked media, unrelated files, forged traversal paths, in-flight cancellation, and corrupted local playback after reselection. Existing transfer tests retain authorization, queue, cancellation, range-resume, and publication checks.

## Verification

All commands run sequentially through the pinned project shell profile:

```sh
nix develop /Users/alexispurslane/Development/bookfin/.cache/dev-shell --command bash -c '<command>'
```

| Command | Observed result |
| --- | --- |
| `flutter test --reporter expanded` | 269 application tests passed. |
| `flutter analyze` | No issues found. |
| `bash test/sdk_link_test.sh` | Passed additive linking, repeatability, refusal to overwrite existing tools, and missing-SDK cases. |
| `dart format --output none --set-exit-if-changed lib/downloads lib/catalog/screen.dart test/downloads` | Eleven files checked; zero changes. |
| `bash tool/bookfin build-android` | Debug ARM64 APK built successfully. Dependency compilation reported obsolete Java source/target 8 warnings. |
| `bash tool/bookfin build-web --release` | JavaScript release built successfully. Dependency WebAssembly and Cupertino font warnings remain; no WebAssembly support is claimed. |
| `git diff --check` | Passed. |

The final check log is `/tmp/bookfin-retained-final-checks.log`. Initial behavior failures are in `/tmp/bookfin-retained-red.log`; initial UI failures are in `/tmp/bookfin-retained-ui-red.log`. Restoration and empty-selection failures are in `/tmp/bookfin-retained-restoration-red.log`. The early storage-error failure is in `/tmp/bookfin-retained-storage-error-red.log`. The green UI log is `/tmp/bookfin-retained-ui-green.log`.

The Android build log is `/tmp/bookfin-retained-android.log`. The web build log is `/tmp/bookfin-retained-web.log`. The WebAssembly dry run reported secure-storage and audio-package incompatibilities. The successful JavaScript release does not resolve those dependency limitations.

## Runtime acceptance gap

The authorized follow-up on integrated main `756ae5f` is recorded in
`../evidence/playback/personal-records-fresh-attempt.md`. It stopped before
sign-in after an invalid Settings activity argument and its advised retry.
All 271 host application tests passed again, but retained-storage Android
visibility, removal, and relaunch remain unobserved.

No device or browser operation ran for this ticket. The reader proof owns the emulator. Android interaction, cream/sepia appearance, scrolling, confirmation behavior across account changes, and relaunch behavior still need parent-owned shared Device panel acceptance. Host widget tests and build results do not establish those runtime observations.

No coverage, mutation testing, PR, ticket closure, production server access, or secret input ran. The parent owns independent review, integration, acceptance, and later test hardening.

## Parent account-switch correction

The review found that a pending cancellation write checked its directory against the newly selected account. A regression reproduced the failure: after switching accounts, the canceled audio edition returned as waiting for Wi-Fi.

Each download record now retains its owning account key. Pending writes validate containment against that immutable key, with the existing directory and symbolic-link checks intact. Account restoration waits for commands accepted before the switch to finish all their record writes. New commands wait for restoration separately.

Two cases cover switching away during multi-file cancellation and immediately switching back before cancellation finishes. Returning to the original account leaves the edition canceled. Enabling Wi-Fi starts no media request. All 271 application tests, analysis, formatting, and the Android ARM64 debug build pass through Nix. No new Android runtime, web build, coverage, or mutation result is claimed. Independent correction review and integration remain pending.
