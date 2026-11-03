# Native reader packaging evidence

Date: November 2, 2026, America/New_York. Some UTC timestamps fall on November 3.
This milestone follows `b81b472`; parent-owned sync R1/R2 are not included.
No artifact here is an accepted final sync build or an approved distribution.

| File | Evidence |
| --- | --- |
| initial-build.txt | Normal APK with production reader code builds in 112.9 seconds before native notices are added. |
| initial-inventory.txt | Original APK v2 signature, 16 KB ZIP alignment and packaged native library inventory. |
| notices-red.txt | The actual reader license stream initially has no native notices. |
| pre-notices-apk-rejected.txt | The real notice stream passes after implementation, but the old APK is rejected for missing notice assets. |
| full-host-analysis-build.txt | SDK checks, 398 Flutter tests and clean analysis pass. One optional real-plugin test is skipped. Normal APK build includes all 29 checked native notice assets and pinned PDFium bytes. |
| replacement-build.txt | Actual host and Android modified-library builds, host KF8 conversion, APK replacement, signature/alignment/notice verification and entry-by-entry comparison pass. No device installation. |
| replacement-production-importer.txt | All four actual production MOBI import/cache/error tests pass with the modified host library, not the original pinned library. |

The notice-complete original APK SHA-256 is
`fd5879f0672b73f8c1a8ff774e427214de3a38a26b71d92f47c67f81540dcaf3`.
The modified APK SHA-256 is
`a2574c211f3c3ec73a469975ec418acd5702197e7cf4e7e3a1bb1d4a53316801`.
Only `lib/arm64-v8a/libmobi.so` changes outside signing metadata. PDFium remains
`de19db1c0fb33579bca6ace903af7ccb9d03ad1d3f6c5202970d8d79d7538303`.

`docs/research/native-reader-packaging.md` gives matching source-export, build,
replacement, and installation coordination instructions. Actual source export
is performed after the complete milestone is committed so the export cannot
silently omit uncommitted implementation.

`t3-ipk1` remains open for Android loading/ordinary reading after replacement,
the actual distribution/source/installation-information approach, and qualified
compliance review. Android PDF/MOBI lifecycle, offline, fonts and accessibility
acceptance also remain open. No runtime OCR work or engine selection is claimed.
No device, acceptance route, or acceptance fixture server is touched.
