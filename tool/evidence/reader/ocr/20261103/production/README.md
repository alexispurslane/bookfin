# Bundled English production-source milestone

This directory records implementation checks, not Android app acceptance.
The original task base is `2d43820a179ad0e8e433fd5f3eb83ce66c9bdd33`.
The parent's missing-Container correction `44d53af` was cherry-picked as
`78ce699`. The ticket file was retained, and PDF admission keeps both its
verified-byte selection and the English text-supply wiring.

## Meaningful failing checks

| Evidence | Observed behavior before its correction |
| --- | --- |
| `text-supply-red.txt` | A real image-only PDF returned absent text instead of recognized candidate text. |
| `ownership-red.txt` | Download removal, account replacement and source removal each allowed stale recognition to return candidate text. |
| `native-worker-red.txt` | The production worker did not admit the page operation. |
| `explicit-retry-red.txt` | Explicit English recognition left the unreliable extracted text unchanged. |
| `cancel-retry-red.txt` | Retry during native drain returned the canceled page's empty result. |
| `close-failure-red.txt` | Recognition-close failure retained the PDF owner and made runtime shutdown fail again. |

These failures exercised behavior. Syntax and missing-reference failures are not
counted as red tests. Earlier widget fake-async and CLI-path setup attempts are
not acceptance evidence.

## Passing checks

`full-tests.txt` runs `nix develop --command bash tool/bookfin test`.
It includes shared Android SDK checks, the native macOS hook checks, the actual
production Java worker coordinator, and every Flutter reader/sync regression.
All 453 Flutter tests pass, with three existing opt-in skips.
`analysis.txt` runs `nix develop --command bash tool/bookfin analyze`.
`cache-admission-green.txt` includes the parent's extensionless Jellyfin Book
admission tests and account/source/version/corruption cache cases.
`lifecycle-green.txt` includes retry during native drain and recognition-close
failure cleanup. `quality-green.txt` exercises conservative text-order fallback.

`host-native-green.txt` recognizes the pinned generated-English scan with an
actual Nix Tesseract executable and the exact selected English model. The full
reference matches after whitespace normalization. The test uses actual PDFium
rendering, the production coordinator/cache and existing resume/bookmark stores.
Host versions are Tesseract 5.5.3 and Leptonica 1.87.0, not the selected Android
5.5.1/1.85.0 native stack. Its transport shim does not prove Android JNI behavior.

The Java check uses the real production worker and a held engine boundary.
It proves bounded admission, one native engine owner, safe close/drain ordering
and failed-initialization retry. Widget checks use controlled text/image
boundaries to test the existing reader's reflow, search, source-page navigation,
recognition state and original-page fallback.

## Remaining gates

No device or simulator action, install, live server, distribution or ticket
closure belongs to this milestone. Research-only offline/lifecycle reports remain
separate. The normal-reader Android run on `4ae8c6c` does not accept OCR.
Production OCR still needs normal-app Android checks after a fresh offline
install, cache reuse, active cancellation, source/account/removal changes,
recognition failure/retry, approved-layout inspection and resource measurements.
English is the only supported language. Full historical pages remain unscored.
No table/column repair, general accuracy threshold or legal clearance is claimed.
Coverage and mutation campaigns wait for user acceptance.

`docs/ocr-implementation.md` records state ownership, exact pins, notices and
remaining distribution/source/installation-information decisions. The build
handoff records its exact source commit, APK hash and matching-source inventory
separately after a clean, checked source commit.

## Verified normal-app build

The final APK and matching source come from clean source commit
`5fca4a23843c57d4ba162d94500e700bd036266f`. Later changes to this evidence directory
and the ticket do not change that APK or its source stamp.

| Artifact | Value |
| --- | --- |
| Normal app | `dev.bookfin.bookfin`, `lib/main.dart`, ARM64 debug |
| APK | `.cache/artifacts/ocr-20261103-production/bookfin-5fca4a2-arm64-debug.apk` |
| APK bytes | 131217891 |
| APK SHA-256 | `5b0f6d3d451bfb36671e8fc19084f2084064e21d4edc26fdbf8d982308a0bf32` |
| Source directory | `.cache/artifacts/ocr-20261103-production/source-5fca4a2` |
| Bookfin source tar SHA-256 | `d24275341d56639f881081b3832422d8e13725678b9c53744df68ec16a388404` |
| Source manifest SHA-256 | `5fb0a2cf5fba9264995e7eec954ba74d224e238ccdfb956963baca479b10b083` |

`build.txt`, `apk-verification.json`, `reader-apk-verification.json`, `badging.txt`
and `provenance.json` record the exact candidate. All 13 native libraries are
ARM64 and have at least 16 KiB ELF load alignment. Package alignment passes at
16 KiB. All four OCR libraries match the pinned AAR byte for byte. The exact
4,113,088-byte English model is stored uncompressed. OCR notices, existing reader
notices, application permissions, package identity, APK v2 signature and the clean
source stamp pass verification. The APK's Bookfin source stamp is not Google's
separate APK SourceStamp signing feature.

The first build stopped at a Gradle digest-import namespace collision, recorded
in `gradle-configuration-failure.txt`. The next compilation succeeded, but package
verification rejected unrequested native architectures, recorded in
`package-architecture-red.txt`. The final source derives dependency architecture
filters from Flutter's requested targets. It does not impose an ARM64-only
product restriction on other requested builds.

`post-build-tests.txt` repeats all 453 tests and the SDK/native worker checks on
the final source, with the same three existing opt-in skips.
`post-build-analysis.txt` reports no issues. `daemon-stop.txt` records stopping
the single daemon in this checkout's Gradle home. No owned Gradle or Kotlin
compiler process remains. No other process was stopped.

Raw command logs and upstream license files preserve their original whitespace.
The source-only diff check excludes those verbatim evidence/license inputs.
This build was not installed. Android OCR behavior, resource measurements,
approved reader layout and distribution terms remain parent-owned gates.
