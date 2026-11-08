---
id: boo-dtoq
status: open
deps: []
links: []
created: 2026-11-08T02:49:00Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Keep the dev shell's pinned inputs safe from Nix garbage collection

On Nov 7 the APK build failed because /nix/store/...-tesseract4android-4.9.0.aar was missing: a garbage collection removed the dev shell's fetchurl inputs (BOOKFIN_OCR_MODEL, BOOKFIN_OCR_ANDROID_AAR, BOOKFIN_OCR_ANDROID_SOURCE, BOOKFIN_OCR_MODEL_LICENSE), and nix develop does not fetch them again. The fix that worked was 'nix build --no-link .#devShells.<system>.default.<VAR>' for each one. Keep a GC root for the dev shell (for example 'nix develop --profile .nix/dev-profile', ignored by git), or make tool/bookfin build-android realize these inputs before Gradle runs.

