---
id: t0-ys9g
status: in_progress
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

## Notes

**2026-11-03T19:38:50Z**

Renewed-authorized parent diagnosis: before restart T3 screenshot shows Flutter red error screen, Null check operator used on a null value. Error screenshot retained; exact throwing location remains unproved. Relaunch restores accessible controls. Removed both owned downloads, signed out/closed, restored network0/1/1 and retained media mute. Read-only audit verifies all70 retained identities/payload hashes/pending flags unchanged, original28 pending, SQLite integrity ok, no app process. Binding released shutdown:false. Evidence tool/evidence/reader/integrated/20261103/cancel-diagnosis/. Investigate and reproduce app cancellation rendering failure before another acceptance run.

**2026-11-03T19:53:58Z**

Implementation from ee2a2c1: full ReaderScreen + PdfViewport widget red and five real BundledEnglishText coordinator cases reproduce Null check operator used on a null value at starting lib/reader/screen.dart:279:65, not the viewport _text! lead. Cancel publishes a valid source-page address with no total page count; screen guarded only page, then asserted pages. Screen now requires both optional quantities before dividing and labels a known page without a fabricated total. No OCR/address/download-owner changes. Regression cases hold raster/native completion, verify native drain before retry, late-result rejection, retry success/failure with original fallback, and unresolved page-two character-10 bookmark preservation plus selected-text reuse. Nix focused 43 passed; full project shell checks plus 489 Flutter tests passed, three existing gated skips; analysis clean. Evidence tool/evidence/reader/cancel-rendering/20261103/. Packaging follows from a clean committed candidate. No device actions, children, coverage/mutation, te-rtok changes, or Android acceptance. Ticket remains in progress for parent review/integration and device acceptance.
