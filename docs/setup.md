# Development setup

This setup targets macOS on Apple Silicon and Android.
The Nix shell is `devShells.aarch64-darwin.default`.
Other host platforms are not declared or tested.
Keep the main checkout at `~/Development/bookfin`.
T3 worktrees, separate checkouts for individual tasks, use the same flake.

## Pinned tools and writable files

`flake.lock` pins nixpkgs to `fe13242281a67641c0102cdb1087f0ebe586c7df`.
The pinned nixpkgs source supplies Flutter, Dart, Java, and all Android native tools.
No native dependency requires a separate source derivation.
The shell also supplies FFmpeg, the video encoder used by T3's Android stream.
Android license acceptance is declared in `flake.nix`.
Updating the lock is a toolchain change, not part of routine setup.

| Tool | Version |
| --- | --- |
| Flutter | 3.47.4 stable |
| Dart | 3.13.3 |
| Java | 21.0.11 |
| Android platforms and build tools | APIs 35 and 36; build tools 36.0.0 |
| Android command-line tools | 19.0 |
| Android emulator supplied by Nix | 37.1.11 |
| Android system image | API 36, Google APIs, ARM64; revision fixed by nixpkgs |
| Android NDK, the native compilation tools | 28.2.13676358 |
| CMake | 3.22.1 |
| Gradle | 9.3.1; download checksum recorded in its wrapper settings |

The shell sets `JAVA_HOME`, `ANDROID_HOME`, `ANDROID_SDK_ROOT`, and `FLUTTER_ROOT`.
Do not put these variables in a shell profile.
The Nix SDK is read-only.
API 35 supports the native dependencies of local appearance preferences and the selected pdfrx PDF reader through jni.
API 34 remains available for existing plugins.
The Bookfin application still compiles against API 36.
Its `cmdline-tools/latest` link points to the pinned command-line tools, not a moving download.
Flutter's dependency cache is `.cache/pub`.
Gradle's cache is `.cache/gradle`.
Both paths belong to the current checkout and are ignored by Git.
Flutter also generates ignored `android/local.properties` with local SDK paths.

From the checkout root, run:

```sh
nix develop --command flutter pub get
nix develop --command bash tool/bookfin doctor
nix develop --command bash tool/bookfin test
nix develop --command bash tool/bookfin analyze
```

`doctor` reports host tools, including iOS tools that this Android ticket does not use.
The normal test command runs SDK-link safety, compiles Android reader file access against APIs 35 and 36, and runs all Flutter widget tests.
A widget test runs the Flutter screen without starting an Android emulator.
It does not prove Android behavior.

## Android discovery in T3

T3's server runs outside the project shell.
It already uses `~/Library/Android/sdk` on this machine.
That existing SDK had an emulator and platform tools, but no current command-line tools.
Changing `ANDROID_HOME` inside a terminal does not change the running T3 server.

Use this explicit, additive compatibility link:

```sh
nix develop --command bash tool/bookfin link-t3-sdk "$HOME/Library/Android/sdk"
nix develop --command bash tool/bookfin emulator-create
```

The link command creates only `cmdline-tools/latest` inside that existing SDK.
It refuses to replace an existing directory or a different link.
It can run again when its own link already matches.
It does not replace the existing emulator, platform tools, platforms, or images.
Remove only that exact link to undo this discovery change.
If a later toolchain update changes its target, inspect the old link before removing it.
Then rerun the link command.

The emulator command creates the virtual device named `bookfin-api36` under `~/.android/avd`.
A virtual device stores the mutable Android system and app state.
The command does not replace a virtual device that already exists.
Its image path is absolute and points into the project-managed Nix SDK.
This lets T3 use the pinned image while keeping the existing host SDK intact.
The running T3 server still uses its existing emulator executable.
That existing executable is version 35.5.10 on the implementation machine.
To use the Nix emulator executable too, launch the T3 server from the project shell in a later session.
Do not restart the current shared T3 server during a build or test.

Nix garbage collection can remove tools that no running shell retains.
A persistent garbage-collection root, a reference that retains the tools, prevents this.
Create that reference from the checkout root:

```sh
nix develop --profile .cache/dev-shell --command true
```

Refresh T3 devices, then use `device_list` and `device_open`.
Pass the returned host and device identifiers.
Use the exact device-bound `agent-device` command returned by `device_open` for all app launches and input.
For shared human input, add `--no-test-ime` to that command's `open` operation.
An input method is the Android service that receives keyboard text.
The automation command otherwise selects a keyboardless test input method on emulators.
That test input method supports automated text entry but hides Android's on-screen keyboard.
The phone's own keyboard does not automatically open when a streamed Android field gains focus.

If an earlier automated session already selected the test input method, restore Android's keyboard through the Device panel:

1. Open Android Settings, then System, Keyboard, and On-screen keyboard.
2. Turn off Agent Device Test IME. Keep Gboard enabled.
3. Reopen Bookfin with `--no-test-ime`, tap the text field, and use the Android keyboard inside the streamed screen.

Do not launch Android through `flutter run`, adb, simctl, or ssh.
ADB, Android's build-and-debug bridge, remains available for installing APKs and reading logs.

Build and install the boot shell after T3 opens the emulator:

```sh
nix develop --command bash tool/bookfin build-android
nix develop --command adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
```

Replace `emulator-5554` if T3 reports a different running device identifier.
Open `dev.bookfin.bookfin` with the returned device-bound command.
Then attach Flutter without relaunching the app:

```sh
nix develop --command bash tool/bookfin attach-android emulator-5554
```

The initial attachment and Android hot reload were verified. A later attachment after replacing the APK repeatedly retried a stale Dart VM service endpoint. That session was detached with lowercase `d`. If attachment repeatedly reconnects, detach rather than leave it running. Reliable reattachment after APK replacement is tracked in ticket `t3-4isz`.

Use `device_screenshot` to inspect the screen.
If a device tool fails, follow its recovery advice once.
If it still fails, stop device driving and report the exact error.

## State-preserving hot reload

Hot reload changes running Dart code while retaining the current screen state.
Hot restart starts Dart again and loses that state.
A browser page reload also loses this fixture's text.
The fixture is `tool/reload_probe.dart`, separate from `lib/main.dart`.
Its text field is temporary test state, not a saved Bookfin record.

For a browser test, run:

```sh
nix develop --command bash tool/bookfin probe-web
```

For an Android test, build and install the fixture:

```sh
nix develop --command bash tool/bookfin build-probe-android
nix develop --command adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
```

Open the installed app through T3's device-bound command.
Then attach to the fixture:

```sh
nix develop --command bash tool/bookfin attach-android emulator-5554 --target tool/reload_probe.dart
```

Use this procedure on each target independently:

1. Enter a distinctive note in `Shared setup note` through the shared preview or Device panel.
2. Change the visible `Reload marker: before` text in the fixture to `Reload marker: after`.
3. Press lowercase `r` in the Flutter terminal. Do not press uppercase `R`.
4. Confirm the marker changes and the entered note remains.
5. Restore the source marker and use lowercase `r` again.

Stop the fixture before using the boot shell on the same target.
For Android, rebuild and reinstall the boot shell, open it through T3, and attach again.
The fixture and boot shell share the same temporary application identifier.
They are not two separate installed apps.

## Web preview and phone access

Both web commands bind only to `127.0.0.1:7357`.
Use T3's integrated browser and its environment-port navigation for port 7357.
Do not expose an unauthenticated public development server.
The pinned Flutter version enables web hot reload by default.
Validate that configuration with the fixture rather than assuming that a rebuild preserves state.

T3 can share the Device panel through the user's authenticated environment connection.
The user must open this same thread on their phone and enter a distinctive setup note.
The desktop must show that note in the same running emulator.
Repeat this observation separately for the web preview.
A successful desktop preview does not establish phone access.
The implementation agent cannot confirm the phone's view without the user's observation.

## T3 project scripts

`docs/t3-scripts.json` contains proposed project settings.
Register these only after this checkout is integrated into the main project.
Preserve scripts that another task adds before integration.
Every script runs from the project checkout through `nix develop`.
None starts on worktree creation or after an unrelated task settles.
The web script opens the integrated preview on the loopback address.
Android launch and attachment still follow the explicit device selection above.

## Not implemented

This scaffold has no Jellyfin connection, books, downloads, playback, reader, or sync.
The full approved appearance, bundled fonts, motion, and sunset behavior belong to later tickets.
Android background playback, audio routing, storage durability, and network policy are not tested here.
Release signing and physical Android testing remain separate work.

## Observed diagnostic warnings

On November 1, 2026, Android debug builds and the web build passed on this machine.
The diagnostic command still reported unaccepted licenses for optional SDK packages.
The required Android SDK license was declared in Nix, and both Android builds completed.
Do not run an interactive license installer against the read-only Nix SDK.
The SDK manager also warned about nixpkgs' legacy `ndk-bundle` compatibility link.
That warning did not prevent emulator creation or compilation.

The diagnostic command reported unavailable iOS simulator SDK files and missing CocoaPods.
This project does not build iOS.
The web build reported an expected-font warning for `CupertinoIcons`, although the shell uses Material icons.
The web build completed and the Android screen displayed its book icon.
Flutter also reported four newer dependency versions outside the pinned SDK's constraints.
The dependency lock was not changed to chase those versions.
