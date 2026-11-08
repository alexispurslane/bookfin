---
id: boo-2sev
status: closed
deps: []
links: []
created: 2026-11-08T14:31:02Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Build the Android app from x86_64 Linux and WSL2 with Nix

flake.nix pins system = aarch64-darwin, so the dev shell exists only on Apple Silicon Macs. The Android build itself (Flutter, JDK, androidenv SDK and NDK, the Android PDFium and Tesseract archives) has no macOS dependency. Darwin-only parts: nix/darwin-native-tools.nix (xcrun, sigtool), the host PDFium archive pdfium-mac-arm64 in nix/reader-native.nix, the .dylib paths PDFIUM_LIBRARY and BOOKFIN_MOBI_LIBRARY used by host tests, ocr.hostEngine, and test/darwin_native_tools_test.sh in tool/bookfin. Google ships Android build tools and the NDK for x86_64 Linux, not aarch64 Linux, so the target is x86_64-linux (which also covers WSL2 on Windows).

## Acceptance Criteria

nix develop works on x86_64-linux; tool/bookfin build-android produces the debug APK there; host tests pass or are skipped with a stated reason; the darwin shell is unchanged; README and index.html list Linux and WSL2 as build hosts.

