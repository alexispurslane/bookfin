# Fresh-install acceptance attempt, November 3, 2026

This focused test lane started from parent commit
`2d11125e21066d15f0ff92cee1f29a44357cecad`. No child agent ran.
No production file, existing evidence helper, APK, source archive, plugin, or
retained device was changed. The lane stopped before installation or sign-in.
This is a provisioning report, not a runtime acceptance pass.

## Provisioning and T3

An Android virtual device (AVD) is a saved emulator configuration.
The lane created only `bookfin-accept-20261103-db111f95` at
`/Users/alexispurslane/.android/avd/bookfin-accept-20261103-db111f95.avd`.
Its registration file is the adjacent `.ini` file.
The project-managed Nix `avdmanager` used the existing pinned
`system-images;android-36;google_apis;arm64-v8a` image and `pixel_7` device.
It allocated a 2 GiB RAM configuration and four virtual CPU cores.
`provision.txt` records successful creation and registration.
No existing AVD was overwritten, reset, stopped, or deleted.

T3 discovery initially exposed only the retained `local/emulator-5554`.
After provisioning, T3 also exposed the new unbooted target:
host `local`, device ID `bookfin-accept-20261103-db111f95`.
Thus discovery succeeded. This report does not call the target unavailable
merely because there was initially only one emulator.

One T3 `device_open` attempt failed with:

> The emulator process for "bookfin-accept-20261103-db111f95" exited with code 1 before coming online.

The full response and invocation are in `device-open-error.txt`.
No bound `agent-device` command was returned. The response suggested manual
boot. That suggestion conflicts with the task's Device-panel-only boot rule.
The task also restricts post-failure investigation to read-only host tooling.
Therefore the manual command was not run. No alternate binding, direct emulator
boot, adb UI action, private database write, or retry evasion occurred.

## Read-only host findings

T3 attempted to launch
`/Users/alexispurslane/Library/Android/sdk/emulator/emulator`.
The new AVD names its image through this relative path:
`system-images/android-36/google_apis/arm64-v8a/`.
That path does not exist under the host SDK. The host SDK instead contains
the distinct `google_apis_playstore` image.

The required image does exist under the project-managed SDK:
`/nix/store/in52zy1w2yv0197h7553n827h8f03x8k-bookfin-android-sdk`.
Its `source.properties` and `system.img` were verified read-only.
The project-managed emulator reports version `37.1.11.0`.
Installed T3 host source confirms SDK discovery checks environment settings,
tools on PATH, and the platform's default SDK. The observed T3 invocation did
not use the emulator selected within `nix develop`.

For comparison only, the retained AVD already has an absolute Nix image path
in its configuration. It was read but not edited. No shell profile, host SDK,
host process environment, or AVD configuration was changed after the failure.
The observed image-resolution mismatch is a concrete setup problem. Native
stderr was not supplied, so this report does not establish the sole cause
of exit code 1. Follow-up work is tracked in `td-e1sx`.

## Acceptance status

| Check | Result | Exact limit |
| --- | --- | --- |
| Separate disposable AVD | Pass | Created with pinned project tools; T3 discovers its own target ID |
| T3 boot and bound command | Blocked | Exit code 1 before online; no bound command |
| Exact APK, source archive, plugin hashes | Pass | Read-only host hashes match all three required values |
| No earlier app or private OCR model/cache | Unverified | Only AVD configuration exists on disk, but Android package/private-state inspection was not possible |
| Fresh-install first recognition fully offline | Blocked | No installation, download, radio change, route, model copy, or recognition occurred |
| Reflow, search, original, saved place/bookmark | Unverified | No runtime actions |
| Cache reuse and offline process restart | Unverified | No runtime actions |
| Durable Unicode pending and explicit Sync now | Blocked | No account or new personal action was created |
| Lost acknowledgment and repeat sync | Unverified | No real plugin fixture was started |
| Cross-account OCR ownership | Unverified | No sign-in or account change |
| Original 28 pending recovery | Still blocked separately | Prior bounded inventory found no authentic matching backup; not a UTF-8 transfer failure |

UTF-8 is the text encoding used for the Unicode upload checks.
No new-account success, old-account recovery, duplicate-free retry, or plugin
readback is claimed for this lane. Earlier resumed acceptance remains separate.
Native callback ordering, broader hardening, UI simplification `boo-4ixi`,
physical-phone checks, and release/legal approval remain outside this lane.

## Artifacts for the physical-phone trial

The unchanged APK remains at:
`/Users/alexispurslane/.t3/worktrees/bookfin/t3-f29350e1/.cache/artifacts/bookfin-d8e1021-cancel/bookfin-d8e1021-arm64-debug.apk`.
It was not installed, rebuilt, published, or sent to a physical phone here.
Its clean source commit is `d8e1021fef2be69291d135594a45d556570c235f`.
The adjacent source archive remains `source/bookfin-source.tar`.

| Artifact | SHA-256 |
| --- | --- |
| Normal ARM64 debug APK | `8b31c7448f746226453d4677f944c9ba4f5668f657bba8015f94973372744e09` |
| Source archive | `3dd0c18fb2cdc3b94e8831f12b4ef92d573bccd73392a626b3c46de1dae45f60` |
| Unchanged Storage 0.1.1.0 plugin | `3b0de5ca1df39baf67c786079898b1ee3b0b09d3bdb86d00ece8a7f5731a9105` |

## Cleanup and audit

Final T3 discovery shows the retained emulator still booted and the new AVD
unbooted, with no open bindings. The new AVD contains only `config.ini`.
It remains registered for supported follow-up. There is no new pending state
or sole fixture recovery path to preserve. No service, route, credentials,
private app copy, download, or installed test package was created.
No app or settings action occurred, including media-volume changes.

The retained `local/emulator-5554` was never opened or operated in this lane.
Its 79 actions and original 28 pending actions are the previous lane's counts,
not a fresh private-database measurement. Its media mute and signed-out/closed
state were not changed here. The previous report remains the source for those
app-state facts. No claim is made that the old pending account was recovered.

Run the focused read-only audit through the project shell:

```sh
nix develop --command python3 tool/evidence/reader/integrated/20261103/fresh-install/audit.py
```

The audit checks artifact hashes, image-path mismatch, the new AVD inventory,
and the recorded T3 results. It writes `public-audit.json` without credentials,
tokens, or raw account identities. An audit pass is not a runtime test pass.
No ticket was closed. The parent owns integration and any renewed device lane.
