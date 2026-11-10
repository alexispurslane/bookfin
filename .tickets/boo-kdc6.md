---
id: boo-kdc6
status: open
deps: []
links: []
created: 2026-11-10T22:14:31Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fval
---
# Restore emulator gesture input for PDF performance acceptance

Parent acceptance on 2026-11-10 opened fresh T3 session for bookfin-api36 emulator-5556, installed profile word_view_probe and observed its scanned PDF rendering. agent-device swipe failed with COMMAND_FAILED: injectInputEvent returned false; the prescribed --debug retry failed identically (java.lang.IllegalStateException, dispatched unknown). Stopped UI actions per host rules. Diagnostic request 148198c7e27baab5 in /Users/alexispurslane/.agent-device/remote-diagnostics/t3-130af3b15755d2b73cadb1b2/requests/148198c7e27baab5.ndjson. Earlier emulator-5554 was reserved by another session; never reused/closed it. No Pixel input. Need functioning approved T3 input before page-turn/reopen/view-switch performance acceptance. Do not substitute adb input or another UI driver.

## Acceptance Criteria

Approved device-bound T3 gesture input succeeds on an owned emulator session, then tb-fb6j records actual page-turn and view-switch performance. No claim based solely on host tests or initial rendering.
