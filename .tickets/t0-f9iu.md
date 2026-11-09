---
id: t0-f9iu
status: open
deps: [t0-i4kg]
links: []
created: 2026-11-09T21:19:35Z
type: task
priority: 2
assignee: Alexis Purslane
parent: t0-t799
---
# Run the chosen voice through ONNX Runtime in a worker isolate, with durations

Package the official ONNX Runtime library for Android (and the host for tests) and call its C API through dart:ffi from one long-lived worker isolate. Load the voice model on request, synthesize one sentence or clause per call, return PCM and, for Kokoro, the per-token frame durations. Respect a thread count that the caller sets. Pin the model files and their hashes. The voice download follows the media network policy.

