---
id: td-k7fj
status: open
deps: []
links: []
created: 2026-11-13T01:47:29Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Keep the 32-bit ARM Android build of the speech library off ARMv8.2 instructions

Found during boo-737n. native/speech/CMakeLists.txt sets GGML_CPU_ARM_ARCH to armv8.2-a+dotprod+fp16 for every Android ABI. A configure of the armeabi-v7a ABI with the NDK toolchain printed 'Adding CPU backend variant ggml-cpu: -march=armv8.2-a+dotprod+fp16', so the 32-bit library holds ARMv8.2 instructions too. Nothing was run on a 32-bit phone. A plain 'flutter build apk' puts the armeabi-v7a library in the APK, and a phone with a 32-bit Android, as many budget phones with Cortex-A53 cores have, loads it. The run-time test of boo-737n covers arm64 only: the 32-bit kernel reports the features with other bit numbers, and partly in AT_HWCAP2. The x86_64 ABI is not affected: its configure printed no arch flags. Two ways to fix it: 1. Set the ARMv8.2 arch only for the arm64-v8a ABI, so the 32-bit build uses the base ARMv7 NEON instructions and speech there is slower. 2. Give no model on 32-bit ARM (bs_open returns NULL), so speech falls back to matched chapters there. A third way is to stop building the armeabi-v7a ABI.


## Notes

**2026-11-13T02:06:45Z**

Review of boo-737n, 2026-11-12, to do with this ticket: the arch string in native/speech/CMakeLists.txt and CPU_NEEDED in native/speech/bookfin_speech.c are tied only by comments. Make drift fail the build: move CPU_NEEDED into a header, compile one small file with -march=${GGML_CPU_ARM_ARCH}, and in it _Static_assert each ACLE macro against its bit (__ARM_FEATURE_DOTPROD, __ARM_FEATURE_ATOMICS, __ARM_FEATURE_CRC32, __ARM_FEATURE_QRDMX, __ARM_FEATURE_FP16_SCALAR_ARITHMETIC, __ARM_FEATURE_FP16_VECTOR_ARITHMETIC). Use #error for a feature that needs AT_HWCAP2 (MATMUL_INT8, SVE, BF16) and for any of these features under __arm__. The cheapest fix of the 32-bit case: set the arch only when CMAKE_ANDROID_ARCH_ABI is arm64-v8a. The release steps already build only android-arm64, and PDFium is packaged for arm64 only, so no APK that the project ships carries the 32-bit library.
