---
id: t3-4isz
status: open
deps: []
links: []
created: 2026-11-01T22:59:47Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Make Android debugger reattachment reliable after APK replacement

After the setup fixture APK was reinstalled, a second Flutter attach session connected and then repeatedly retried a stale Dart VM service endpoint. The session was detached rather than left reconnecting. The earlier Android state-preserving hot reload demonstration succeeded. Reproduce and establish a bounded, reliable reattachment procedure without launching apps outside the T3 device-bound command. Keep private Dart VM tokens out of notes and logs shared with users.

## Acceptance Criteria

Reinstall the debug APK, open it through the device-bound command, attach using the Nix shell, and demonstrate state-preserving hot reload again. Document recovery that does not leave an unbounded reconnect loop.
