---
id: t2-y0ce
status: open
deps: []
links: [boo-ohud]
created: 2026-11-02T23:45:24Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Clarify bound Android session close and application process cleanup

Observed November 2, 2026 during boo-ohud acceptance on local/emulator-5554. Bound agent-device close reported Closed: t3-0687f49c0b8d6053d5bd7d54, then device_close(shutdown:false) released the binding. Subsequent allowed adb readback pidof dev.bookfin.bookfin still returned the prior process11695. The app was already signed out, own download removed, settings restored, and fixture servers/routes stopped. A single explicit close dev.bookfin.bookfin attempt through the same returned executable failed exit127 with No such file or directory because release removed the executable. No binding reset or adb UI fallback. Need a supported sequence that closes the named app before release and verifies its process state; do not claim session-close success proves app-process termination. Evidence: docs/evidence/reader/android-remaining.md and tool/evidence/reader/android-remaining/cleanup.json.

## Acceptance Criteria

Supported bound named-app close confirms Bookfin no longer runs before device release. Restore only owned state; no binding-reset workaround or adb UI fallback. Distinguish session release from app termination and retain exact readback evidence.
