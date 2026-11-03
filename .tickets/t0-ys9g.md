---
id: t0-ys9g
status: open
deps: []
links: []
created: 2026-11-03T19:07:13Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Keep Android reader inspection usable after active OCR cancellation

November 3 normal APK source 71af288: a complete fresh snapshot of a 1600x4000-point, 22-image English scan showed Recognizing English text and Cancel recognition. The bound command dispatched Cancel; settle observation became unavailable. The next complete snapshot failed COMMAND_FAILED: Android snapshot helper returned insufficient foreground app content (mw123qnc-f55b5356). The one advised retry failed identically (mw1248f2-2610843c). Diagnostics report the Bookfin foreground app with one meaningful node, below the helper threshold of two. App process still exists; crash buffer is empty. No app crash, successful drain, completed cancellation, or native interruption established. Device UI work stopped without fallback. Evidence tool/evidence/reader/integrated/20261103/remaining/. Two new owned downloads, signed-in running app, and network 1/0/0 require a separately authorized cleanup lane under the stop rule.

## Acceptance Criteria

Investigate whether the reader loses accessible semantics or the helper rejects a legitimate sparse reader window. Restore supported inspection without replacing the binding or using an alternate UI engine. Under explicit renewed authorization, finish owned-download removal, sign-out/close, network 0/1/1 restoration with media muted, and then run still-unproved normal-app cancel/drain/retry and active-departure acceptance. Preserve every retained action.

