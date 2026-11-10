---
id: te-rtfa
status: in_progress
deps: []
links: []
created: 2026-11-10T19:31:29Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Keep transparent pixels transparent when tinting word-image bands on Android

Found while recovering tb-22fu on dedicated bookfin-tb22fu emulator. Impeller draws opaque ink across gaps between atlas sprites because the ink color matrix creates opacity from transparent black. Reproduce with a transparent source pixel in an ink band, retain the source alpha in the alpha row, and verify the actual Android view. Fix carried with tb-22fu; parent closes after integration.


## Notes

**2026-11-10T19:32:37Z**

Reproduced on dedicated Android emulator in docs/evidence/reader/word-view/before-transparent-gaps.png. Two host behavior tests (cream and night transparent ink-band pixels must leave paper visible) failed before the change. Replaced the color matrix alpha constant with the source-alpha coefficient, keeping transparent black transparent while preserving opaque scan pixels. Carried in tb-22fu recovery branch; parent closes after integration.

**2026-11-10T19:47:50Z**

Rebuilt the Android probe after the alpha fix and captured scan-cream-20.png, scan-night-40.png, text-layer-night-40.png, text-layer-cream-40.png, and text-layer-next-screen.png on dedicated bookfin-tb22fu. Inspected the captures: opaque gaps are gone. Evidence and reproduction instructions are under docs/evidence/reader/word-view/README.md. No physical device or private source used.

**2026-11-10T20:31:40Z**

Parent integrated with tb-22fu. Combined word renderer regressions and full 2560-test suite pass, including transparent-pixel behavior. Child Android evidence records corrected cream/night rendering. Pixel acceptance remains with user.
