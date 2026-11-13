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

