---
id: boo-gxm8
status: in_progress
deps: []
links: []
created: 2026-11-01T21:37:34Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Set up Nix Flutter Android and shared T3 testing

Provide a pinned dev shell and Android SDK discovery for the T3 device host. Register working T3 run/test scripts. No global toolchain installation. Resolve the missing command-line tools reported during planning.

## Design

docs/plans/bookfin.md

## Acceptance Criteria

Build and test via nix develop. Open Android through device_list/device_open. Demonstrate state-preserving hot reload and shared phone interaction. Confirm browser preview and phone access independently.

## Implementation notes — November 1, 2026

Builder checkout: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-38292988`.
Branch: `t3/nix-flutter-android-scaffold`.
Base: `5a7347ec9cf1b220a015c9dd7728001b81a9eb48`.
The ticket remains in progress for parent review and integration.

### Delivered

- Pin nixpkgs, Flutter 3.47.4, Dart 3.13.3, Java 21, Android API 36, command-line tools 19, emulator 37.1.11, ARM64 image, NDK, CMake, and FFmpeg through the Nix shell.
- Generate only Android and web platform scaffolds. Replace the generated greeting with a clearly labeled cream/sepia Bookfin setup shell. Leave the approved mockup unchanged.
- Add a separate temporary text-field fixture for shared input and state-preserving hot reload. No catalog, connection, download, player, reader, or sync behavior is implemented.
- Add `tool/bookfin` commands, safe SDK discovery linking, behavior tests, setup notes, and six proposed T3 script settings in `docs/t3-scripts.json`.
- Do not register the scripts on the main project before integration. No remote or PR was created.

### Host changes outside Git

The existing host SDK was preserved. Only its previously absent `cmdline-tools/latest` link was added.
It points to `/nix/store/ahp82jjy0znf9l2ps98pj3bkl3zgrkgd-bookfin-android-sdk/cmdline-tools/latest`.
The SDK-link test proves repeated calls are safe and existing tools are not replaced.
The project virtual device is `~/.android/avd/bookfin-api36.avd`.
Its image path points into the pinned Nix SDK.
The running T3 server uses the existing host emulator 35.5.10; the project shell separately provides 37.1.11.
The persistent Nix shell reference is `.cache/dev-shell` in this checkout.
No global toolchain was installed and no shell profile was changed.

### Verification

| Operation | Outcome |
| --- | --- |
| `nix develop --command bash test/sdk_link_test.sh` before implementation | Meaningful red: expected discovery link was absent |
| Boot-shell widget tests before implementation | Meaningful red: Bookfin title and honest unavailable-library message were absent |
| Reload-fixture widget test before implementation | Meaningful red: editable text field was absent |
| `nix develop --command bash tool/bookfin test` | Pass: SDK-link safety test and all three Flutter widget tests |
| `nix develop --command bash tool/bookfin analyze` | Pass: no issues |
| Dart format, Nix format, Bash syntax, proposed-script JSON | Pass |
| `nix develop --command nix flake check --no-build` | Pass: declared development shell evaluates |
| `nix develop --command bash tool/bookfin build-android` | Pass: boot-shell debug ARM64 APK, installed and opened through the device-bound command |
| `nix develop --command bash tool/bookfin build-probe-android` | Pass: fixture debug ARM64 APK, installed and opened through the device-bound command |
| `nix develop --command bash tool/bookfin build-web` | Pass: `build/web`; nonfatal CupertinoIcons font warning |
| Android hot reload | Lowercase `r` reloaded one library in 400 ms. Marker changed from before to after while `Android retains this note` remained in the field |
| Web hot reload in T3 Preview | Lowercase `r` reloaded in 148 ms. Marker changed while `Web retains this note` remained. Browser `performance.timeOrigin` stayed `1793572829340.5`, proving no page reload |
| Normal web boot shell in T3 Preview | Pass: rendered `Bookfin`, `Your library starts here.`, and the unavailable-library message |
| T3 Android discovery and open | Pass: host `local`, running device `emulator-5554`, virtual-device name `bookfin-api36` |
| Phone viewing | User explicitly confirmed seeing the same emulator on their phone |
| Phone tapping | User reported tapping into the field; device snapshot independently showed the field focused |

Both hot reload marker edits were restored to `before` after verification.
No hot restart was used as a substitute for hot reload.
The normal Bookfin boot shell was independently installed, opened, and inspected on Android.
Android before/after screenshots and the boot-shell screenshot are in `/tmp/bookfin-android-before.png`, `/tmp/bookfin-android-after.png`, and `/tmp/bookfin-android-shell.png`.
The boot-shell APK is also copied to `/tmp/bookfin-boot-shell.apk`.

The first `device_screenshot` request failed with: `Device screenshot failed: The device hub could not complete the request. Call device_list to check the device state, and device_open if it needs to be reopened.`
The advised `device_list` showed the device still open. One screenshot retry succeeded, as did later screenshots.

### Shared-input limitation and recovery

The user reported that the phone's keyboard did not open after tapping the streamed field.
The device reported the automation helper input method `com.callstack.agentdevice.imehelper` and no visible keyboard.
`open --no-test-ime` alone did not restore an already selected helper input method.
Through the device-bound command, the builder opened Android Settings and disabled Agent Device Test IME under System → Keyboard → On-screen keyboard.
The builder reopened Bookfin with `--no-test-ime` and verified that Gboard was visible with the field focused.
The user can tap that Android keyboard inside the streamed emulator screen.
Do not claim successful phone text entry until the user enters a note and it is observed.

### Diagnostic limits and handoff

`doctor` exits successfully but reports optional SDK package licenses and unrelated iOS/CocoaPods gaps.
SDK tools warn about the Nix `ndk-bundle` compatibility alias. These warnings did not prevent either Android build.
The web compiler reports a nonfatal CupertinoIcons font warning. Dependency resolution reports four newer versions outside the pinned constraints.
Coverage and mutation testing remain with the later hardening ticket.
Release signing and physical Android validation are not part of this scaffold.

The Device panel remains open for shared phone testing. The Android app is the temporary fixture, not the product shell.
Device-bound session: `t3-a3bcd04d55e92d42b9aace45`.
Device command: `/Users/alexispurslane/.t3/userdata/device/targets/t3-a3bcd04d55e92d42b9aace45/agent-device`.
The parent must obtain its own device-bound command through `device_open`, not reuse or close this session.
The integrated preview tab is `tab_3_41842020-cae3-49e1-8112-034559a9b773` on loopback port 7357.
The normal web boot shell remains served by terminal session `45360`, running `nix develop --command bash tool/bookfin web`.
No Android debugger is currently attached. After a later APK replacement, a second attach session connected but repeatedly retried a stale Dart VM service endpoint. The builder detached that session with lowercase `d`; it is stopped. This does not invalidate the earlier successful Android hot reload demonstration, but reliable reattachment after replacement remains follow-up ticket `t3-4isz`.
The standard Android build output currently contains the temporary fixture APK. Rebuild the boot shell with `nix develop --command bash tool/bookfin build-android` before installing the normal shell.
Phone access to the integrated browser preview remains independently unconfirmed.
No unresolved product design fork was found.
