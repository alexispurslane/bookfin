---
id: boo-737n
status: open
deps: []
links: []
created: 2026-11-12T23:41:02Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Make sure that the CPU has the instructions that the speech library needs before the model loads

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: plausible, the Pixel 8 is not affected. native/speech/CMakeLists.txt:28-32 builds ggml for `armv8.2-a+dotprod+fp16` with no runtime test of the CPU. On an ARMv8.0 phone, the first speech window executes an illegal instruction and the whole process dies, playback included, at each listening session. In `bs_open` (native/speech/bookfin_speech.c:52-73), read `getauxval(AT_HWCAP)` for `HWCAP_ASIMDDP` and `HWCAP_FPHP` and return NULL when one is missing, so speech falls back to matched chapters.

