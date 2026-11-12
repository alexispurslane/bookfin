---
id: t2-uyth
status: in_progress
deps: [t2-8kxe, t2-67a3]
links: []
created: 2026-11-11T22:44:17Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-vh77
---
# Transcribe a window in a low-priority speech worker

The speech runtime: one long-lived worker isolate that loads the bundled model, then decodes and transcribes a window on a native thread at low priority with a thread cap, a reduced audio context and a token cap. It gives the heard words with their times. It closes after an idle time to free its memory. It never starts on the path to the first useful frame. Engine rule 1.


## Notes

**2026-11-11T23:15:52Z**

Built: lib/speech/speech.dart (Speech: one KeptWorker isolate holds the model, hears one window at a time, stops after 2 minutes idle and frees the model's native memory first; findSpeechModel locates the APK asset through the bookfin/speech channel on Android, or BOOKFIN_SPEECH_MODEL on a dev machine). native/speech bs_open reads the model from a byte range of a file (the APK in place); bs_hear decodes and transcribes on a new pthread at nice 10 (QoS utility on macOS), audio context cut to the window (min(1500, ceil(s*50*1.1)+32)), single segment, max_tokens = s*6+8. Threads: 2 in the background, 4 when a person waits, one core left free. MainActivity answers bookfin/speech model with the APK path, offset and length. test/speech/speech_test.dart runs real whisper on the Mac: words, word times, a later window, past the end, no model, the calling isolate keeps running, the model leaves memory when idle.

**2026-11-12T01:28:13Z**

Review fix (B6, D4): a KeptWorker whose isolate stops, or cannot start or make its state, fails its jobs with WorkerStopped (an Exception, so callers refuse) and is forgotten, so the next job starts a new worker instead of waiting on a dead port. A job after close fails with WorkerStopped too. Tests: test/speech/worker_test.dart.
