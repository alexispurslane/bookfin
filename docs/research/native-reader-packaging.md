# Native reader packaging candidate

Date: November 2, 2026 (America/New_York). Tickets: `boo-mx5i`, `t3-ipk1`.
This is an engineering preparation, not a release license approval.

## Inputs and notices

The application uses libmobi 0.12 and a converter that includes its upstream
`tools/mobitool.c`. `native/NOTICE.txt` names that use and its LGPL-3.0-or-later
terms. The unchanged LGPL and GPL texts, upstream converter/XML-writer notices,
and miniz notice are bundled as application assets. The complete PDFium
chromium/8125 Android archive license bundle is also retained byte for byte.
Software licenses are accessible from the account sheet. The reader license
stream handles UTF-8 and Latin-1 notice files without replacing characters.
Flutter supplies the other Flutter/Dart dependency notices.

`nix/reader-native.nix` pins the libmobi source, host PDFium archive, Android
ARM64 PDFium archive, and full GPL text with hashes. `flake.lock` pins the Nix
toolchain. The converter and CMake flags are in `native/mobi/`.

The normal `tool/bookfin build-android` command prepares the dependency-owned
PDFium native-asset cache from that pinned Android archive before building. It
then checks the APK's actual PDFium bytes, native converter/library entries,
and every bundled native notice against the source manifest. This avoids
accepting an unverified tag-only native-hook download as the normal candidate.

```sh
nix develop --command python3 tool/reader/prepare_notices.py
nix develop --command bash tool/bookfin build-android
nix develop --command python3 tool/reader/native_package.py verify build/app/outputs/flutter-apk/app-debug.apk
```

`prepare_notices.py` regenerates the tracked notice assets from the pinned
inputs. Review any resulting changes. The build verifier does not regenerate or
silently repair missing notices in the APK.

## Matching source export

After committing a candidate and checking that its worktree is clean, export:

```sh
nix develop --command python3 tool/reader/native_package.py sources .cache/artifacts/native-reader-source
```

The new directory contains the complete committed Bookfin checkout as a Git
source archive, exact libmobi source, complete LGPL/GPL texts, these instructions,
and a SHA-256 manifest tied to the source commit. This includes the application
source, converter source, patches, build scripts, lockfiles, and native source
pins. Existing directories are refused rather than overwritten.

Extract `bookfin-source.tar` into a new working directory. Extract the supplied
libmobi source archive when inspecting or changing that dependency. The normal
build uses the same source through Nix. An interface-compatible local replacement
can be passed to CMake with `BOOKFIN_LIBMOBI_SOURCE`; no global SDK, profile, or
system library needs to change.

## Replacement preparation

Use an existing disposable debug signing key, never a production key:

```sh
nix develop --command python3 tool/reader/replacement_proof.py build/app/outputs/flutter-apk/app-debug.apk .cache/artifacts/native-reader-replacement --keystore "$HOME/.android/debug.keystore"
```

This script copies the pinned libmobi source into a new private output directory.
It changes only `mobi_version()` to return a named replacement marker. It builds
the modified library and converter for the host, loads the modified library,
and converts the pinned public KF8 sample into a checked EPUB container. It then
builds Android ARM64 from the same modified source, replaces only the APK's
`lib/arm64-v8a/libmobi.so`, aligns it for 16 KB pages, and signs with the supplied
debug key. Signature verification, notice verification, pinned PDFium identity,
and an entry-by-entry comparison verify the resulting package. Non-signature
application entries other than the replaced library must remain identical.

The script creates no device connection and installs nothing. Its JSON result
records that Android installation has not occurred. It never writes a global
debug key. The normal app's Dart code and converter bridge are unchanged.

## Installation information and remaining gates

The parent coordinates installation of the normal and modified candidates with
the exclusive Android acceptance lane. The original test APK and replacement
must use the same disposable signing key for an in-place replacement. A key
change is not grounds to uninstall an application containing unsynced records.
Preserve existing records and downloads; do not reset application data as a
substitute for demonstrating replacement.

The acceptance lane must show ordinary downloaded MOBI reading after installing
the replacement and record both package identities and the matching source
manifest. Host conversion and a signed Android package do not prove Android
loading, font callbacks, runtime replacement, or ordinary reader operation.

Before release, the parent still needs to approve the actual distribution/source
delivery and installation-information approach, review any store/signing and
reverse-engineering terms, and obtain a qualified compliance review. No
production source offer, legal clearance, store eligibility, or full LGPL
compliance claim is made here. `t3-ipk1` remains open until its complete acceptance
criteria are met. EPUB/PDF Android runtime and accessibility gates also remain.
