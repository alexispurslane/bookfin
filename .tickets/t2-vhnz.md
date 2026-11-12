---
id: t2-vhnz
status: open
deps: []
links: []
created: 2026-11-12T01:24:28Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-z3is
---
# Decode audio windows in the Linux dev shell

native/speech/bookfin_speech.c decodes audio with the NDK on Android and ExtAudioFile on macOS. On Linux, decode() returns -1, so speech search in the Linux dev shell falls back to matched chapters, and test/speech/decoder_test.dart and the hearing tests of test/speech/speech_test.dart skip there. Add a Linux decoder, for example through FFmpeg's libraries from nixpkgs in the speech derivation (nix/whisper.nix), and remove the skips. Found in the boo-vh77 review (t2-67a3).

