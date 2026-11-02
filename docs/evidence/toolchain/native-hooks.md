# Pinned macOS tools for native Dart hooks

Date: 2026-11-02. Ticket: t7-fyql. Starting commit: `261d50eb48dbe78288d44419d692e27268430a78`.
The SDK verification is recorded separately in `sdk35.md` and commit `84d817e8faca95d99b16becfce96ba200034df4a`.

## Reproduced failures

Removing the compatibility override alone leaves version 2.4.4 in the existing lock.
The reproduction therefore also ran `flutter pub upgrade path_provider_foundation` through the root Nix shell.
It selected path_provider_foundation 2.6.0 and objective_c 9.5.0.
No unrelated dependency upgrade was requested.

| Reproduction | Result before the corresponding fix |
| --- | --- |
| `flutter test --reporter expanded test/boot_shell_test.dart` without the override | The objective_c hook fails before tests run. The compiler receives `error: unable to find sdk: 'macosx'` as its sysroot. It cannot find `assert.h` or `Foundation/Foundation.h`. |
| Native-tool test with SDK variables removed | Exit 1. `FAIL: Native hook SDK discovery failed: error: unable to find sdk: 'macosx'`. |
| Same test after SDK discovery is fixed, with unpatched pinned sigtool | Exit 109. A real unsigned Objective-C library compiles, but signing fails with `The following argument was not expected: --timestamp=none`. |
| Reader compatibility test after sharing the SDK discovery fix | The pdfium_dart hook treats xcbuild's missing-iOS diagnostic as an SDK path and fails with `PathNotFoundException`. xcbuild returns 255 and writes the diagnostic to stdout. |
| Added SDK-error regression before error normalization | Exit 1. `FAIL: SDK discovery must report errors on stderr, not as an SDK path on stdout.` |

These are executed tool and hook failures, not assertions about source text.
The missing-iOS case also exposed a protocol requirement in the selected native_toolchain_c resolver.
That resolver needs exit 1, empty stdout, and a diagnostic containing `cannot be located` on stderr.
The regression exercises that requirement for iPhone, iPhone simulator, and unknown SDK names.

## Changes

The root shell and the reader research shell import one module, `nix/darwin-native-tools.nix`.
It uses the existing pinned apple-sdk, xcbuild, and sigtool sources from nixpkgs.
No flake lock or source hash changed.
The new Nix file was staged before Git-flake evaluation.

The tools select macOS SDK 14.4 for each xcrun invocation, including hooks without inherited SDK variables.
Both SDK argument orders work. Conflicting caller SDK variables do not change the selected SDK.
Unavailable SDK queries fail with the protocol described above.
Other xcrun operations still execute the pinned backend.
No iOS SDK is supplied or pretended to exist.

The local sigtool patch accepts only `--timestamp=none`.
sigtool already produces untimestamped ad-hoc signatures, so this argument requests its existing behavior.
The patch does not skip signing, discard errors, accept timestamp services, or provide Apple certificate signing.
The actual signature writer is unchanged.

Both the root app and selected reader package now use locked path_provider_foundation 2.6.0 without dependency overrides.
The normal root test command includes the native-tool regression and Android platform compile regression.
No HTML or Markdown reader support was added. The `html` parser remains an EPUB implementation dependency.

## Final verification

All commands ran through pinned Nix shells, one build or test job at a time.

| Check | Result |
| --- | --- |
| Root `bash tool/bookfin test` | Exit 0. All 292 Flutter tests pass, plus SDK-link safety, Java compilation against APIs 35/36, and the native-tool regression. |
| Fresh native-hook rebuild | Previous root hook outputs and macOS assets were moved into ignored `.cache` directories before the final test run. The hook regenerated objective_c.dylib, and the root test command returned 0. |
| Root `bash tool/bookfin analyze` | Exit 0. No issues found. The final staged-source run took 5.0 seconds. |
| Root `bash tool/bookfin build-android` | Exit 0. ARM64 debug APK, with automatic SDK downloads disabled. |
| Root `bash tool/bookfin build-web` | Exit 0. Standard JavaScript web output. This is not a WebAssembly build. |
| Research `bash tool/research/readers/epub-compat` | Exit 0. Five compatibility tests pass. Four optional public-corpus tests skip because that separate corpus was not acquired. |
| Research native Android libraries | Exit 0. Pinned shared-SDK NDK builds libmobi, the converter, and the PDF link probe. |
| Selected reader APK in the root shared shell | Exit 0. See `sdk35.md` for the command, alignment, permissions, hash, and package contents. |
| `flutter test --reporter expanded` in the generated reader package | Exit 0. Five tests pass with both native-hook dependencies enabled and without the compatibility override. |
| Signature checks on real hook outputs | `/usr/bin/codesign --verify --strict` returns 0 for root objective_c.dylib and research objective_c.dylib, libpdfrx_pdfium_gate.dylib, and libpdfium.dylib. |
| `nixfmt --check flake.nix nix/darwin-native-tools.nix tool/research/readers/flake.nix` | Exit 0. |
| `git diff --check` | Exit 0. |

The focused native-tool test starts with an unsigned Objective-C dynamic library.
It calls the real pinned signer with Flutter's arguments and verifies the signature with the operating system.
It repeats forced signing and verifies again.
It rejects timestamp services and unknown options.
Finally it changes a byte in the signed library and requires verification to fail.
The macOS verifier is intentionally the independent operating-system verifier, not a signing substitute.

The final root command was:

```sh
nix develop --command bash -c 'bash tool/bookfin test; result=$?; printf "ROOT_TEST_EXIT=%s\n" "$result"; if [ "$result" -ne 0 ]; then exit "$result"; fi; /usr/bin/codesign --verify --strict build/native_assets/macos/objective_c.dylib; bash tool/bookfin analyze'
```

The output records `ROOT_TEST_EXIT=0`. The enclosing Nix command also returned 0.
After removing trailing whitespace from patch-file context, the staged-source formatter, root tests, analysis, reader host tests, and real signature checks passed again.
Root Android, root web, and shared-SDK reader packaging then passed again, sequentially, with both recorded APK hashes unchanged.

Android builds used:

```sh
export GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.workers.max=2 -Dorg.gradle.project.android.builder.sdkDownload=false"
```

This command ran inside the root Nix shell, not the user's shell profile.
The shared SDK remained read-only and supplied platforms 34, 35, and 36. Platform 37 was not added.

The root APK is `build/app/outputs/flutter-apk/app-debug.apk`.
Size: 93,548,290 bytes.
SHA-256: `269977fe04840a1cc834de74bd9ccf18e69bcd1d889b47ae2679c0bc53febc54`.
Debug APK hashes identify these local outputs, not reproducible release builds.

## Preparation observations

The first reader compatibility run after tool repair lacked generated MOBI-to-EPUB fixtures.
It was not counted as a tool regression or a passing check.
The pinned mobitool regenerated `_out/mobi6-plain.epub`, `_out/mobi6-palmdoc.epub`, and `_out/alice.epub` from committed fixtures.
The repeat then passed five compatibility tests.
The reader native build used the root shell's NDK through `BOOKFIN_NDK`, with the research shell providing libmobi and PDFium inputs.
Only the root shared shell packaged the reader APK.

An intermediate root test command printed 292 passing tests but returned 1.
The final full command was repeated with an explicit inner status, then repeated again after archiving hook outputs.
Both final repeats returned 0. Only those verified exits are counted above.

## Warnings, host state, and cleanup

The standard web build reports existing WebAssembly incompatibilities in secure-storage and audio dependencies, plus a Cupertino font-family warning.
Those warnings do not prevent the standard JavaScript build, and no WebAssembly support is claimed.
The root Android build reports obsolete Java 8 source/target warnings in a dependency.
The libmobi native build reports a pre-existing NDEBUG redefinition warning.
Native discovery warns about unavailable iOS SDKs and Visual Studio. Neither toolchain is required for this macOS/Android work.
These unrelated warnings were not hidden or repaired.

Memory free percentage was at least 40 percent before builds and tests.
Final verification began with 59 GiB disk space available.
No build or test process was intentionally left running. Gradle builds disabled persistent daemons.
Test scratch directories clean themselves up.
Ignored dependency caches, APK/web outputs, logs, and archived prior hook outputs remain in this worktree for inspection.
The attempted forced deletion of generated hook output was refused by the host command guard. Archiving it instead allowed a fresh build without deletion.

The existing host SDK link and global Xcode selection are unchanged from `sdk35.md`.
No user profile, global SDK, production Jellyfin server, or private credential was touched.
No device, emulator, or browser was started or controlled. No app was installed.
No coverage, mutation testing, subagent, PR, or ticket closure was performed.
Both assigned tickets remain in progress for orchestrator integration.
