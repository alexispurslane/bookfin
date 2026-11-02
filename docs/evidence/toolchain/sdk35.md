# Shared SDK reader packaging

Date: 2026-11-02. Ticket: t9-26f6. Starting commit: `261d50eb48dbe78288d44419d692e27268430a78`.

## Baseline finding

The assigned baseline already includes Android platforms 34, 35, and 36 in the shared SDK.
Commit `bbe0ae5f3f4d7e95fcc889c5a4a3f44ef4cc7e92` preserves platform 35 while adding platform 34 for an existing plugin.
The ticket's missing-platform failure does not reproduce at this baseline.
No platform change is needed, and no failure was manufactured by removing an installed platform.

The shared SDK is `/nix/store/in52zy1w2yv0197h7553n827h8f03x8k-bookfin-android-sdk`.
Its platform links point into the pinned Nix store.
Platform 37 is absent. The existing platform 34 is preserved.

## Checks

| Check | Result |
| --- | --- |
| `nix develop --command bash test/sdk_platform_test.sh` | Exit 0. Real Java code for Android file access compiles against platforms 35 and 36. |
| `nix develop --command bash test/sdk_link_test.sh` | Exit 0. Temporary SDK links are additive and repeatable. Existing tools and missing host SDKs are refused. |
| Native reader libraries | Exit 0. The pinned NDK builds libmobi and the conversion library. |
| Selected reader APK through the shared root shell | Exit 0. pdfrx 2.11.0 and jni compile and package without SDK installation. |
| APK offline manifest | No INTERNET permission. |
| APK alignment | `zipalign -c -P 16 4` exits 0. This checks Android package alignment for 16 KiB pages. |

The platform regression compiles code, not the text of `flake.nix`.
The APK contains compiled jni classes, `libmobi.so`, `libreader_convert.so`, `libpdfium.so`, and `libpdfrx_pdfium_gate.so`.
It also contains the PDF, EPUB, MOBI fixtures and their license files.

After the documented research fixture and native-library preparation, the final packaging command was:

```sh
nix develop --command bash -c 'printf "SHARED_ANDROID_HOME=%s\n" "$ANDROID_HOME"; export GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.workers.max=2 -Dorg.gradle.project.android.builder.sdkDownload=false"; bash tool/research/readers/android-apk'
```

`ANDROID_HOME` names the shared read-only SDK.
`GRADLE_OPTS` disables automatic SDK downloads and persistent Gradle processes, and limits Gradle to two workers.
The build took 60.7 seconds for `assembleDebug`.
The log contains no SDK installation attempt.
The research-only Android shell was not used for APK packaging.
The working tree also contained the t7-fyql native-tool cleanup and updated research dependency lock.

Output: `tool/research/readers/_out/flutter-smoke/build/app/outputs/flutter-apk/app-debug.apk`.
Size: 102,994,305 bytes.
SHA-256: `685d325dfb0eb8f1e225d8de7295494b605c561506276848ffd850ca1546ce15`.
This locally generated debug package is not a release package or a reproducible-build guarantee.

## Preserved host state and limits

The existing host SDK link remains `/nix/store/ahp82jjy0znf9l2ps98pj3bkl3zgrkgd-bookfin-android-sdk/cmdline-tools/latest`.
Its `avdmanager` executable still resolves. No host link was replaced.
The global Xcode selection remains `/Applications/Xcode.app/Contents/Developer`.
No shell profile or global SDK was changed.

One build ran at a time. Memory free percentage was 47 percent before APK packaging, with 63 GiB disk space available.
No device, browser, or emulator was started or controlled. No APK was installed.
No production Jellyfin access, credentials, coverage, or mutation testing was used.
Packaging does not establish Android runtime behavior or private-library compatibility.
The ticket remains in progress for orchestrator integration and closure.
