---
id: t8-jj2s
status: in_progress
deps: []
links: [boo-9wgg]
created: 2026-11-02T18:08:45Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Restore the visible EPUB page instead of the chapter opening

Authorized Android acceptance of203f870 through merge ae8dcd9 and exact fresh APK a7c85ad40777950a1f797b1b6c35e7647855cb27d026cd11dc34a8c7b4f253da renders chapters, but reopening twice loses a later visible page. Before close, actual UI begins Harbour passage5 and app-private saved CFI is epubcfi(/6/4!/4/16/1:91). Back then Read returns The lantern room heading. Occurs with downloaded unmodified synthetic EPUB and own fixture server unavailable. Not a missing-save observation: disk readback proves later CFI existed before second reopen. No table in fixture. Screenshots18-21 and filtered location-readback.json in android-corrected evidence. No app changes. Separate from known R1 table normalization, R2 failed store snapshot retry, R3 missing chapter/progress UI, R4 duplicate appearance calls.

## Acceptance Criteria

On normal Android app, move to a later page, establish persisted visible-start location, leave and reopen, and verify the same text remains visible. Repeat across process restart with server unavailable. Add meaningful regression and identify rendering/layout versus state-restoration cause. Keep existing bookmarks and source verification intact.


## Notes

**2026-11-02T18:17:50Z**

Filtered actual preference readback in tool/evidence/reader/android-corrected/location-readback.json proves epubcfi(/6/4!/4/16/1:91) persisted before second reopen, then header CFI /4/2[note]/1:0 after reopen. First screenshot pair18-19 shows loss. Repeated settled Read snapshot showed chapter opening; late screenshot21 instead shows Book details without a planned intervening Back, so do not call it a reader capture. Timestamped Chromium renderer termination code-1 lines occur near intentional exits and before unexpected details; exact causal link unknown. No missing-write assumption or production app edit. Parent owns investigation/integration.

**2026-11-02T20:22:25Z**

Named integrated acceptance of f8868495509d9100146c3cc24835fada98ebaaf3 still FAILS. Fresh normal APK and both installed readbacks SHA2564e7350789b0df08d6d23c05fdee8ba9340872e47092660cfe0fd0a7d97975bbc. At20 CSS pixels, first-chapter passage5 and saved epubcfi(/6/2!/4/26/1:0) exist before Back/Read. Reopen shows Visit the lantern room plus passage1, and readback replaces the anchor with passage1. Repeat across process1163->4280 with own real Jellyfin12.4 and observer stopped also fails; downloaded bytes remain original-hash matched. Bookmark restoration to passage5 succeeds before and after restart. At22 pixels, second-chapter epubcfi(/6/4!/4/18/1:100) and exact visible-start text survive reopening, so failure is not universal. Read-only DOM sampling of another20-pixel failure shows initial correct passage5 column, font-loading/layout changes, then an earlier column; original and processed identities unchanged. Logs show no renderer termination during that sampled shift. No runtime configure/display/readerLocation trace was added, and exact callback cause remains unproved. Do not assume missing writes or renderer exit causes. See docs/evidence/reader/android-integrated.md, screenshots04-05,08,14-15, and account-filtered location/layout evidence. Parent should add actual-iframe delayed-layout regression asserting final visible text AND retained anchor. No production edits, closures, or acceptance.

**2026-11-02T21:03:01Z**

Implementation candidate from 5d32393: actual Chromium iframe regression reproduces requested passage-5 CFI being replaced by a layout-derived passage-1 CFI, followed by resize restoration to the wrong column and a chapter-opening saved CFI. Red was observed before production changes, and the final test also fails against both original integrated assets. Rendition.location.start.cfi now owns the current reading address across passive layout reports; intentional page navigation samples a new address. Content hooks/local styles/images/fonts complete before measurement, navigation waits for actual location measurement, existing views reflow before restore, appearance capture is serialized, and fractional-column page labels round to the aligned page. Canonical XML, passive sandbox, source identity, durable storage and theme lifetime remain unchanged. Actual-layout controls cover Next/Previous, bookmark restore, 22/20px appearance, queued appearance, resource failure and fractional geometry. 21 engine tests, 43 focused reader tests, all 353 Flutter tests and analysis pass. Normal main.dart ARM64 debug APK built in 298.4s, SHA256 f5fd6238fc9b34b30836ab079b9f645e3925d8ed5fd93a5d878ddc198fe15d2a. Android acceptance is NOT complete: own sign-in field input failed, its required diagnostic retry failed on an expired reference without dispatch, and device input stopped. Candidate not installed. Own fixture/observer stopped, route removed, binding released shutdown:false. See docs/evidence/reader/layout-restoration.md and tool/evidence/reader/layout-restoration. Parent must independently review/integrate and run Back/Read, offline process restart, bookmark and second-chapter 22px normal-app acceptance. Do not close this ticket or fold in t8-j809.

Parent follow-up: reproduced review F1 loading-view removal and F2 swallowed neighboring-resource errors in real Chromium. Queue resize/disposal/restoration under rendition ownership and propagate Next/Previous errors. New regressions and evidence retained; independent re-review and corrected-head Android acceptance remain required.
