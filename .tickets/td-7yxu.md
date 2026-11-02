---
id: td-7yxu
status: in_progress
deps: []
links: [t7-msmk]
created: 2026-11-02T14:10:11Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Keep the Android fixture route observable across app relaunch

Authorized Android acceptance at main261d50e created its own reverse tcp:7365 route. Basic playback, record persistence, account isolation and retained storage were observed. After the second agent-device --relaunch the reverse list was empty, while owned loopback servers were alive; restoring library selection showed Cannot reach Jellyfin. Navigation and its advised retry then failed, so acceptance stopped. Cause of route loss is unproven. Do not infer a Bookfin networking defect or evade the stop rule. See docs/evidence/playback/current-main-android.md.

## Acceptance Criteria

Before another authorized device attempt, inspect how the normal fixture reverse route survives a T3 app relaunch. Recheck only owned route state after relaunch and stop on host/tool rules. Complete remaining replacement confirmation and personal-record interactions with public credential-free evidence.

## Notes

**2026-11-02T17:33:13Z**

Fresh own Android binding and own tcp7365 route observed before and after one normal --relaunch at d9d238b. 17:24:53Z process3121 and route present; 17:25:11Z process4631 and same route present. Refresh books succeeded through real observer afterward. No repair needed and earlier route disappearance not reproduced or explained. New tb-zqvc stopped readable-EPUB acceptance. Own route removed during cleanup. Evidence docs/evidence/reader/android-candidate.md plus tool/evidence/reader/android-candidate/. Keep open for broader route reliability and remaining prior acceptance.
