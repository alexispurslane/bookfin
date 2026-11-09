---
id: t0-etnk
status: in_progress
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


## Scope (orchestrator, 2026-11-09)

The user chose Kokoro and allowed one test on the Pixel 8 now, described to the user as a 30-minute test. Keep the phone time to about 45 minutes: one sustained 30-minute run of Kokoro fp32 at 4 threads, plus short runs (a few minutes each) for Kokoro at 2 threads, Kokoro fp16, Supertonic 3 and Kitten nano for reference.

## Status (2026-11-09): not measured yet, test app waits on the phone

The phone run did not happen. The T3 launch command failed with DEVICE_IN_USE: a stale agent-device session from 2026-11-07 (t3-1d501db2f62c9df22f84352f) holds the Pixel. The user then chose to run the test later with one tap. docs/research/on-device-tts.md has Pixel 8 estimates from Mac runs until then.

What is on the phone: the throwaway app dev.bookfin.ttsbench (source in tool/research/tts_bench/), its models (Kokoro fp32 and fp16, Supertonic 3 int8, Kitten nano fp32, 697 MB in all), the book text and plan.json in /storage/emulated/0/Android/data/dev.bookfin.ttsbench/files/. Bookfin itself was not touched.

How the user runs it later:

1. Charge the phone above 60 percent, then unplug it.
2. Make sure that nothing plays.
3. Open the app "ttsbench" from the app drawer. It shows "ttsbench: running" and keeps the screen on.
4. Do not use the phone for about 42 minutes, until the screen says "ttsbench: done". The phone gets warm.

One launch runs five plans in order: kokoro-fp32-t4 for 30 minutes, then kokoro-fp32-t2 (3 min), kokoro-fp16-t4 (3 min), supertonic-t4 (2 min) and kitten-t4 (2 min). The app writes every event to results.jsonl, with Android's thermal status, thermal headroom, battery level, battery current and battery temperature every 30 s. So no computer needs to be attached during the run.

Afterwards, an agent does this:

1. Pull the results: `adb -s <pixel> pull /storage/emulated/0/Android/data/dev.bookfin.ttsbench/files/results.jsonl` and the three passage WAV files beside it (Kokoro fp32, Kokoro fp16, Supertonic).
2. Summarize them: `python3 -I tool/research/tts_bench/scripts/summarize.py results.jsonl`.
3. Replace the estimates section of docs/research/on-device-tts.md with the measurements and the verdict.
4. Uninstall the app with `adb -s <pixel> uninstall dev.bookfin.ttsbench`. This also deletes its files.

The app reads only Android's thermal status and headroom, not CPU temperatures. If an agent is attached during the run, `tool/research/tts_bench/scripts/monitor.sh` also records CPU temperatures and core clocks through adb.
