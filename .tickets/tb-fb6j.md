---
id: tb-fb6j
status: in_progress
deps: [tb-9mcf, tb-mfkk, tb-fi98, tb-bmmm, tb-zx7r, tb-valc, tb-nkz5, tb-m8xo, boo-wfg1, boo-lj72, boo-kdc6]
links: []
created: 2026-11-10T02:33:42Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Accept PDF word reflow on the Pixel 8 and tune its word size

W10 of docs/plans/pdf-word-image-reflow.md (Device acceptance). Use the T3 device tools only. Open the three fixtures and one scanned book from the user's library. Screenshots of the word view in cream and night at sizes 14, 20 and 40, and of the text view. Tune _wordSizeRatio once against an EPUB at size 20. Measure the time from a turn to the first screen of a page with cached text, the time from a turn to a never-recognized scanned page's first word screen and to its text, graphics memory over ten turns, and dropped frames on turns inside a page. Use the emulator numbers of tb-bmmm as the baseline.

## Acceptance Criteria

The first screen of a page with cached text shows within 400 ms on the Pixel 8, or the ticket records the measured time and a follow-up ticket. Graphics memory stays within the band bound. Turns inside a page drop no frame. Screenshots and measurements are saved under tool/evidence and shown to the user for acceptance.


## Notes

**2026-11-10T20:10:25Z**

User accepted the Nihil Unbound crop repair and Trim margins toggle on the Pixel 8. Remaining product scope is word-image reflow (the printed words cut into images and wrapped to the screen), with its planned interactions. Do not repeat crop/toggle acceptance unless integration changes that behavior.

**2026-11-10T21:36:52Z**

Pixel 8 now has combined word-view update ef280c1 (flash fix 22e8453, drop caps a89130c, whole-line Text 280dc46). In-place install passed after 2595 tests/21 skipped and clean analysis/format. User owns phone input and acceptance. Three-view selector tb-9mcf and selection tb-mfkk remain running separately. Coverage/mutation hardening remains pending combined user acceptance.

**2026-11-10T21:49:43Z**

Selection update installed successfully in place on Pixel 8 (adb install -r; no phone UI operated). Built clean source d5b3eb70aa7b24a4de8b0caa7aefa07101b03aa7, including selection merge b3ab841. APK SHA256 eb2531b0173f53509ac7d043448eaf2dc72157f0f2d38e8003fe13137c6c0fae. Build, native/OCR packaging, signature and 16 KiB alignment checks passed. Logs: /tmp/bookfin-selection-phone-{build,install}.log. Combined host checks: 118 focused and 2616 full tests passed, 21 skipped; format and analysis clean. User owns phone acceptance; Android accessibility is not yet verified. Three-view selector tb-9mcf remains pending. Coverage/mutation hardening remains after combined acceptance.

**2026-11-10T22:09:59Z**

User clarified 2026-11-10: install on Pixel, test on emulator. Parent owns emulator-5554 on local host via newly opened T3 binding; no Pixel UI actions. Current verification uses public fixtures. Keep emulator timings distinct from physical Pixel performance and retain unmeasured original acceptance criteria. Final installation waits for boo-lj72 preference integration.

**2026-11-10T22:14:56Z**

Emulator acceptance attempt: updated tool/reader/word_view_probe.dart to the three-way PdfPageView API and added profile frame-work logs plus awaited turn-to-frame timings. Probe-only analysis passed after removing one unused import. Nix profile build passed (47.1s); APK installed on emulator-5554 before launch disclosed another session reservation, so no launch/input occurred there. Then opened a fresh owned session on bookfin-api36/emulator-5556, installed profile APK, launched through bound agent-device, and observed scanned footnote-page.pdf word images on cream. This is the real reader engine in a probe, not full app or phone acceptance. Both swipe attempt and prescribed debug retry failed with injectInputEvent returned false; stopped device UI. boo-kdc6 tracks tool blocker. No turn latency samples, no successful reopen/view-switch actions, no reasonable-performance verdict. Initial frame logs alone are insufficient. Logs /tmp/bookfin-perf-{profile-build,profile-install-api36,probe-analyze,device-api36,fixtures,cleanup}.log. Stopped only owned HTTP/logcat PIDs and removed only owned reverse mappings. Existing other session was neither reused nor closed. Pixel UI untouched. User requested final Pixel installation after pending preference work.
