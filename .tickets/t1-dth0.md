---
id: t1-dth0
status: open
deps: []
links: [boo-737n, boo-zyx1]
created: 2026-11-13T03:01:50Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112, device-acceptance]
---
# Restore Device panel screen inspection for Android acceptance

During the authorized boo-zyx1 and boo-737n acceptance attempt at main 0643cebc on local/emulator-5556 (bookfin-api36), device_open and bound agent-device open dev.bookfin.bookfin --foreground succeeded. device_screenshot failed twice with: Device screenshot failed: The device hub could not complete the request. Call device_list to check the device state, and device_open if it needs to be reopened. Between attempts, the advised device_list reported the host ready and the emulator booted and already open. The agent stopped device work after the single retry. No build, install, network setting change, playback test, or speech window ran. No existing app data was cleared. Prior boo-gxm8 evidence records the same first failure with a successful retry; this attempt did not recover. Evidence: docs/evidence/android-survey-20261112/acceptance.md.

## Acceptance Criteria

A fresh authorized attempt on the assigned emulator obtains a Device panel screenshot without borrowing or closing another session. Then rerun both tickets device requirements with controlled fixtures and retained app data. Keep Activity removal from Recents distinct from backgrounding and force-stop.
