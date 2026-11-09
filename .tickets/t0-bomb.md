---
id: t0-bomb
status: open
deps: [t0-i4kg]
links: []
created: 2026-11-09T21:19:35Z
type: task
priority: 2
assignee: Alexis Purslane
parent: t0-t799
---
# Keep spoken audio beside the download as Opus segments

SpeechStore: encode PCM to Ogg Opus at 16 kbit/s mono with libopus through dart:ffi, write each segment atomically into .bookfin-speech beside the download, with a timing table per sentence and word. Key segments by publication identity, section, first sentence place, text hash, voice, model and front-end versions. Add the directory to DerivedBookFiles so removal deletes it and storage counts it. No upload path reads it. See 'Saved speech' in docs/research/on-device-tts.md.

