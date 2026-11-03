# Reviewed combined Android candidate

Exact application source: 71af2886e722b7366d4d335622e55e18a151a3e0. Later evidence commits do not change that APK source.

Includes reviewed English-fast OCR through 07814af (main c45c0f9), CSS-aware KF8 restoration through e9089ef (main 9d77b1a), and native UTF-8 request encoding f6fede9 (main 9a9b21f). All prerequisite format/storage changes are present.

Combined required checks: 483 Flutter tests pass, three existing opt-in skips; SDK/platform/native-worker checks pass; analysis clean. Normal Flutter Android build succeeds. Exact model, seven OCR notices,29reader notices, four pinned OCR libraries, all13ARM64 libraries with16KiB ELF/package alignment, allowed permissions, debug signature and exact committed source stamp verify. Packaged epub.js and reader.js byte-match the reviewed runtime assets.

The companion changes only lib/arm64-v8a/libmobi.so; modified host library converts actual KF8, signature/alignment checks pass, and the companion also passes the complete OCR package verifier. No installation is claimed. The build's private main-checkout Gradle daemon was stopped.

artifacts.json binds both APKs and matching source archive. Source export also includes pinned OCR/native source, selected model/license, libmobi source and build/terms documents. This is preparation, not qualified distribution approval.

Actual Android OCR, corrected KF8 visible-position restoration, and Unicode sync acceptance remain to be performed. Preserve the device's existing44retained actions. The earlier fixture account/server was deleted during cleanup: a new account's successful sync cannot establish recovery of the old account's28pending actions. Do not erase, rewrite or relabel those records. Fresh-app-install OCR acceptance must not be claimed from an in-place update.

## Subsequent bounded Android evidence

The exclusive November 3 lane recorded actual OCR, exact Alice passage restoration, companion conversion, and new-account Unicode background sync.
See `android/README.md` and `docs/evidence/reader/android-combined-20261103.md` for observed results and exact limitations.
All original 44 actions remain unchanged, including 28 still pending. New-account plugin readback matches 25 actions, with none pending.
Explicit Sync now, fresh-install OCR, and several OCR lifecycle cases remain unverified.
The failed field-entry recovery required a stop before device cleanup. Host cleanup completed, but sign-out, close, downloads, and networking restoration remain unfinished.
This evidence does not close any ticket or establish overall acceptance.
