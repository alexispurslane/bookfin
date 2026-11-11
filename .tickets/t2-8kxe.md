---
id: t2-8kxe
status: open
deps: []
links: []
created: 2026-11-11T22:44:17Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-vh77
---
# Bundle whisper.cpp and the tiny.en speech model in the Android app

Pin the whisper.cpp 1.9.5 source and ggml-tiny.en-q5_1.bin (32 MB) in the flake's default shell. Build native/speech for Android arm64 with 16 KiB ELF alignment, and for the macOS host so that tests load it. Ship the model as an uncompressed APK asset, as the user decided on 2026-11-11 (no download). Extend tool/reader/ocr_package.py so that prepare copies the model and verify checks its pinned SHA-256 in the APK. Measure the APK size change.

