---
id: t0-etnk
status: open
deps: []
links: []
created: 2026-11-09T21:19:35Z
type: task
priority: 2
assignee: Alexis Purslane
parent: t0-t799
---
# Measure Kokoro, Supertonic 3 and Kitten nano on the Pixel 8

Gate for the voice choice in docs/research/on-device-tts.md. With a throwaway debug build and the user's permission on the user's Pixel 8, measure for each model at 2 and 4 threads: sustained RTF over 30 minutes of a real book, CPU temperature and thermal status, battery percent per hour of speech, peak memory, model load time, and the first clause time with a cold and a warm model. Also measure a Kokoro fp16 export against fp32. Use the passage in docs/research/on-device-tts/passage.txt for intelligibility. Report the numbers in docs/research/on-device-tts.md. Kokoro passes if sustained RTF stays at or below 0.6 with at most 4 threads.

