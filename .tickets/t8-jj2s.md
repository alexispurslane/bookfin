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
