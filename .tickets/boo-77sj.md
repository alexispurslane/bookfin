---
id: boo-77sj
status: open
deps: []
links: []
created: 2026-11-08T17:39:24Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Build the Android APK as a flake package

User request (2026-11-08): a flake build output per platform. First: packages.<system>.apk (at least x86_64-linux, also aarch64-darwin if cheap) that builds the debug APK (and a release APK signed with a key from outside the store, if practical) as a pure Nix build: pub dependencies from pubspec.lock and Gradle dependencies locked as fixed-output downloads (for example nixpkgs' gradle mitm-cache / fetchDeps), the Nix-pinned Android SDK, NDK, PDFium, Tesseract and OCR inputs, and the same package checks as tool/bookfin build-android. This is the base for Tangled CI.

