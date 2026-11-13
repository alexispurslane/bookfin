---
id: boo-737n
status: in_progress
deps: []
links: [boo-zyx1, t1-dth0]
created: 2026-11-12T23:41:02Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Make sure that the CPU has the instructions that the speech library needs before the model loads

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: plausible, the Pixel 8 is not affected. native/speech/CMakeLists.txt:28-32 builds ggml for `armv8.2-a+dotprod+fp16` with no runtime test of the CPU. On an ARMv8.0 phone, the first speech window executes an illegal instruction and the whole process dies, playback included, at each listening session. In `bs_open` (native/speech/bookfin_speech.c:52-73), read `getauxval(AT_HWCAP)` for `HWCAP_ASIMDDP` and `HWCAP_FPHP` and return NULL when one is missing, so speech falls back to matched chapters.


## Notes

**2026-11-13T01:51:00Z**

What changed. On Android arm64, bs_open (native/speech/bookfin_speech.c) now reads getauxval(AT_HWCAP) before every call into whisper and ggml, and returns NULL when a feature is missing. It tests six bits: HWCAP_CRC32, HWCAP_ATOMICS and HWCAP_ASIMDRDM, which -march=armv8.2-a turns on in clang (+crc, +lse, +rdm), HWCAP_ASIMDDP for +dotprod, and HWCAP_FPHP with HWCAP_ASIMDHP for +fp16. The ticket named two bits. The built library also holds LSE atomic instructions in ggml_barrier, ggml_graph_compute_thread and ggml_threadpool_chunk_add, so the larger set is needed. The decision is the pure function bs_cpu_runs_speech(hwcap), which host tests call. A failed test writes one warning to logcat with the AT_HWCAP value. The other platforms keep their behavior.

Dart side. Before this change, a NULL from bs_open threw nothing, but the worker isolate stayed alive without a model, stopped after 2 minutes, and the next window started a new worker that called bs_open again. Speech (lib/speech/speech.dart) now treats a model that the worker cannot load as no model for the rest of the run: it closes the worker, and later windows return null without a worker. Crossings then keeps the landing of matched chapters.

Code at load time. The -march flag reaches only the ggml-cpu target (ggml/src/ggml-cpu/CMakeLists.txt, target_compile_options PRIVATE). The compile commands of the Gradle build show it on ggml-cpu.c and not on whisper.cpp or bookfin_speech.c. The arm64 library has four load-time functions in .init_array: init_have_lse_atomics and __init_cpu_features of compiler-rt, and the static initializers of whisper.cpp and ggml_threading.cpp. A scan of the disassembly found no dot product, half float, LSE, RDM or CRC32 instruction in them or in the 156 functions that they reach by direct calls. So the test in bs_open is early enough.

Verification, all through nix develop on macOS arm64:
- flutter test test/speech test/crossings: 148 tests passed, 0 failed.
- bash test/native/speech_package_test.sh and bash test/native/ocr_worker_test.sh: both passed.
- dart analyze of the four changed Dart files: no issues.
- python3 tool/reader/native_package.py prepare, then flutter build apk --debug --target-platform android-arm64: exit 0, built app-debug.apk with lib/arm64-v8a/libbookfin_speech.so. The disassembly of bs_open calls getauxval(16) and tests the mask 0x101780 before whisper_log_set.
- Red evidence: the test of the worker failed with "Expected: false, Actual: <true>" before the Dart change. Seven of the nine CPU tests failed with "Expected: <0>, Actual: <1>" against a stub that accepted every CPU.

Not done. The Android path was compiled and not executed: no run on an ARMv8.0 phone, and no run on the Pixel 8 or the emulator to see that speech still loads there. The 32-bit ARM Android build gets the same -march and has no test of the CPU (td-k7fj).

**2026-11-13T02:06:45Z**

Orchestrator, 2026-11-12: merged into main. A reviewer passed correctness and design by reading: the six bits and their values are right, the arch flag reaches only the ggml-cpu target, and no race exists on the Dart side. Device evidence so far: `grep -m1 Features /proc/cpuinfo` on four running arm64 emulators lists crc32, atomics, fphp, asimdhp, asimdrdm and asimddp, so the test accepts the emulator CPU. The Pixel 8 was not connected. The ticket stays open until one window is heard on a device with no "lacks an instruction" line under the logcat tag bookfin_speech. Follow-ups are in td-k7fj.

**2026-11-13T02:59:48Z**

Astra-only Android acceptance started from 0643cebc. Task node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-android-survey-acceptance-astra-20261112-1; child thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-android-survey-acceptance-astra-20261112-1; clientRequestId bookfin-android-survey-acceptance-astra-20261112-1. Target codex/gpt-6-astra reasoningEffort xhigh. Assigned local emulator-5556 through device_open and the returned agent-device command. Evidence pending; do not treat launch as acceptance.

**2026-11-13T03:03:38Z**

Device acceptance attempt from main 0643cebc on local/emulator-5556 (bookfin-api36) stopped after two failed Device panel screenshots and the single advised discovery/retry. New blocker t1-dth0 records the error. No speech window ran, no compiled CPU guard execution was observed, and no bookfin_speech logcat was captured. Thus words, absence of the unsupported-instruction warning, and no crash remain unverified. Discovery listed only emulators, with no Pixel 8 or unsupported physical ARMv8.0 hardware. Prior CPU-feature, unit, and disassembly evidence was not repeated or promoted to device acceptance. Evidence: docs/evidence/android-survey-20261112/acceptance.md and device-attempt.json. No build, install, app-data clear, product change, coverage, or mutation job ran. The ticket remains in_progress for the parent.
