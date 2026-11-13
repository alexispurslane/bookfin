---
id: boo-hxmd
status: open
deps: [t1-dth0, boo-56h7]
links: [boo-56h7]
created: 2026-11-13T21:41:47Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Accept Ask-at-Play through Android media controls

Native acceptance retained from integrated implementation boo-56h7. Host callback, persistence, held-seek and restart tests do not establish Android headset, notification or lock-screen behavior. Device inspection is blocked by t1-dth0 after the authorized renewed attempt failed twice. Do not retry or bypass that device failure until access is restored. Parent coordinates this work; no active acceptance delegate exists.

## Design

docs/plans/reading-history.md, Listening choice at Play. User chose external Play from this phone with both places retained and a deferred foreground choice.

## Acceptance Criteria

Record the installed application source identity first. On Android, adopt a newer listening place while the local edition is paused. In-app Play must ask before sound. Real headset, notification and lock-screen Play must start at this phone's place after both places are recoverable in History. Foreground must show the deferred choice once; both answers and cancellation must behave as settled. Check restart recovery and a newer sync while a choice is visible. Record observed audio position, History and Undo, tool evidence, failures and unavailable hardware. Use T3 device_open and its bound command; inspect only with device_screenshot. No acceptance from host mocks or screenshots of an unidentified older build.
