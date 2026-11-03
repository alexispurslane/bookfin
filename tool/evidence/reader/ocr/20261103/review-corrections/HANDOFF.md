# Corrected normal Android APK

The APK source is `0f4084f7c670a1b6866f9543ac7af9f1949ba8a3`.
It is the clean correction commit after `acd233323d06b7ea5e23969278c46c44bfd6758c`.
The later commit that contains this handoff adds evidence and ticket notes only.
It is not the APK source. The earlier `5fca4a2` APK remains superseded, not accepted.

## Exact artifacts

The artifact directory is
`/Users/alexispurslane/.t3/worktrees/bookfin/t3-7b2e5fcf/.cache/artifacts/ocr-20261103-review-corrections`.

| Artifact | Name within that directory | SHA-256 |
| --- | --- | --- |
| Normal ARM64 debug APK, 170,179,115 bytes | `bookfin-0f4084f-arm64-debug.apk` | `8be5a98d9201436fd2d6e7499f48f658471e3ed1ac6f777f5b6404e024f13cea` |
| Exact committed Bookfin source | `source-0f4084f/bookfin-source.tar` | `ee44e6050136f1395f25baeacbfcfaeb6148ab6070c98eacfd468fdc3fddce47` |
| Complete pinned OCR wrapper/native source | `source-0f4084f/Tesseract4Android-4.9.0-source.tar.gz` | `4569f9093d641d13188ba2dd36a74396661eaa3f9e44637ff1cac9a36076a20e` |
| Exact bundled English-fast model | `source-0f4084f/eng.traineddata` | `7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2` |

`source-0f4084f/manifest.json` also binds the model license, complete libmobi source,
LGPL/GPL texts and build/terms instructions. `provenance.json` binds every artifact,
source-export file, verification result and build log by SHA-256.
The packaged clean-source record matches the exported Git archive exactly.
Changed production and test files also match `source-hashes.json` and that archive.

## Verification

| Check | Result |
| --- | --- |
| Final focused reader tests | 53 pass, including actual host recognition with the exact selected English model. |
| Full required checks, repeated after packaging on the clean source commit | 474 pass, three existing opt-in skips. SDK discovery, Android SDK 35/36 compilation, Darwin native hooks and held-boundary native-worker checks pass. |
| Post-build analysis | No issues. |
| Normal application build | Both normal Flutter Android builds pass. The verbose build records the Kotlin and Java compiler tasks and successful APK assembly. No probe target is used. |
| Native libraries | All thirteen libraries are ARM64. All four OCR native libraries match the pinned AAR exactly. PDFium matches its pinned Android input. |
| Model and notices | Exact 4,113,088-byte English-fast model, seven OCR notices and twenty-nine reader notices verified. |
| Alignment | Every native library has at least 16,384-byte ELF load alignment. APK package alignment passes the 16 KiB check. |
| Permissions | All six permissions match the superseded normal APK. No OCR permission is added. |
| Signature | APK v2 signature verifies with one Android Debug signer. This is debug build provenance, not reproducible release signing or an Android SourceStamp attestation. |
| Cleanup | Both build command traps stopped their owned Gradle daemon. Final status reports no Gradle daemons running. No owned Gradle or Kotlin compiler process remains. |

An auxiliary direct Gradle compile invocation failed during settings initialization:
`The settings are not yet available for build.`
`standalone-gradle-limitation.txt` preserves that result. It is not counted as a pass.
The project Flutter build entry point succeeds with its required Gradle invocation.
No source or toolchain change was made for this auxiliary command.

The three skipped tests need opt-in journal-growth evidence or live Jellyfin plugin
fixtures. This run starts no live service. The host engine is Tesseract 5.5.3 and
Leptonica 1.87.0, not the APK's Tesseract 5.5.1 and Leptonica 1.85.0.
Host recognition is not Android OCR acceptance.

## Parent-owned gates

The parent still owns independent review and integration. `boo-suhu` remains in progress.
Normal-app Android OCR acceptance still requires fresh-install offline recognition,
search/reflow/source-page navigation, cache reopening, active cancellation, ownership
changes, failure/retry, memory/latency measurements and approved-layout inspection.
Existing native-reader distribution, replacement, source-delivery, signing/store and
installation-information gates remain open. No release, compliance clearance,
device installation, UI acceptance, PR or publication is claimed.
