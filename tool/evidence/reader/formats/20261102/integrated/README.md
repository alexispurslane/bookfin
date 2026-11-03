# Integrated sync and reader candidate

Runtime source: 40ee5d4 (reviewed sync/format merge 681c168 plus packaging
6a7fb49 and source-export evidence 40ee5d4). No production-source merge conflicts.
Ticket-note conflicts retained both histories.

Pinned Nix shell verification:

    flutter test --concurrency=1 --reporter expanded
    flutter analyze

407 Flutter tests pass, one optional actual-plugin test skipped. Analysis is
clean. This verifies the combined source, including native notices tests.
No new Android runtime, two-device sync, library replacement or legal acceptance
is inferred. Research OCR probes remain separate from this production source.

## Named Android artifacts

Built normal source 27bf44e3eaceb9ea5c5cece0e16f7041bd4bfb2d through
`nix develop --command bash tool/bookfin build-android`. Build succeeds in 58.6s;
29 notice assets and exact pinned PDFium bytes verify. APK is
`.cache/artifacts/bookfin-27bf44e-sync-formats.apk`, 120360441 bytes, SHA-256
`3382fa6d182edc634bb288b7fc45f57c2edd53df0d970461ee768a454f35b97a`.
SDK link/platform/native checks pass; expected negative-case diagnostics remain
in sdk-checks.txt. Dependency deprecation warnings remain in android-build.txt.

Clean-tree source export is `.cache/artifacts/bookfin-27bf44e-source/`;
source-manifest.json binds application archive, exact libmobi and licenses.

Replacement preparation uses the existing disposable Android debug key and
`tool/reader/replacement_proof.py`. Modified host KF8 conversion passes;
signature/alignment and actual package-byte checks pass. Only application entry
`lib/arm64-v8a/libmobi.so` changes. Companion APK:
`.cache/artifacts/bookfin-27bf44e-replacement/bookfin-replacement.apk`, SHA-256
`144de4e96677170c1537d00df0ba9d0c64fe6693cf8b9487ce8d5d8f83ad02af`.
Neither package was installed. Device lane remains independently owned by OCR
measurement. No runtime replacement or qualified compliance approval inferred.
