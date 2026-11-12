---
id: t2-8kxe
status: in_progress
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


## Notes

**2026-11-11T23:00:03Z**

Built: nix/whisper.nix pins whisper.cpp 1.9.5 (nixpkgs source) and ggml-tiny.en-q5_1.bin; the default shell sets BOOKFIN_WHISPER_SOURCE, BOOKFIN_SPEECH_MODEL and BOOKFIN_SPEECH_LIBRARY (a Nix host build of native/speech). The Android build compiles native/speech for arm64 with 16 KiB alignment and forces -O3 for it even in debug. The APK stores the model uncompressed at assets/bookfin-speech/tiny.en-q5_1.ggml (32,166,155 bytes). tool/reader/speech_package.py prepare copies it and its notices; verify checks the pinned SHA-256, that it is stored uncompressed and that it is the only model, and the notices. test/native/speech_package_test.sh covers the refusals. Debug APK: model 32.17 MB + libbookfin_speech.so 5.16 MB (unstripped debug) stored.

**2026-11-12T01:28:12Z**

Review fix (boo-vh77 review B1): the Android decoder loop now ends after 2 s without an answer from the codec, before or after the input ends, and fails at once on a codec error code other than try-again, format-changed or buffers-changed, so a corrupt file cannot hold the speech worker. Checked by building the debug APK; no codec error could be forced on the emulator.
