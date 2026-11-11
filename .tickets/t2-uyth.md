---
id: t2-uyth
status: open
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

