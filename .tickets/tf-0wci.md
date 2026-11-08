---
id: tf-0wci
status: open
deps: []
links: []
created: 2026-11-08T16:27:59Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [platform, macos, licenses]
---
# Check the reader notices against the PDFium that the macOS app bundles

assets/licenses/reader holds the notices of the pinned bblanchon PDFium chromium/8125 Android build, and tool/reader/native_package.py verify checks the APK against it. On Apple platforms pdfium_flutter's link hook replaces pdfium_dart's library, and the macOS app bundles espresso3389's PDFium-chromium-8125 XCFramework (universal x86_64 and arm64), pinned only by its Swift package checksum 4e83df9e…. Check that the notices cover that build, add a macOS bundle check like the APK one, and decide whether to pin the XCFramework in Nix. Found in boo-gnx9.

## Acceptance Criteria

A check of the built Bookfin.app confirms its PDFium build and that the bundled notices cover it.

