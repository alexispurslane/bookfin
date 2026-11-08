---
id: td-7yxu
status: closed
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

**2026-11-02T18:52:37Z**

Additional exclusive-device acceptance at ac6a247 observed own tcp7365 reverse forward before/after five actual process replacements:16636→19040,19040→19648,19648→20173,20173→20625,20625→21004 between18:36:08Z and18:43:01Z on2026-11-02. Final library reselection after retained-file removal succeeded. No route repair needed; earlier disappearance remains unexplained. Own route removed, services stopped, app signed out and binding released without shutdown. Evidence docs/evidence/playback/remaining-acceptance-android.md and processReplacements in remaining-acceptance-runtime.json. No closure or general reliability claim.
**2026-11-02T18:17:50Z**

Corrected reader attempt observed own tcp7365 route before/after two relaunches: online PID9143 to11538, server-unavailable PID11538 to12201. Route remained present throughout, with no repair; real catalog requests succeeded after online restart. Own route removed at cleanup. Does not explain earlier disappearance or prove repeated stability; ticket remains open. See docs/evidence/reader/android-corrected.md.

**2026-11-03T00:54:04Z**

Fresh fc4531c authorized normal-app acceptance created only own port7365 reverse route after initially empty list. Route remained observed after named app restart and interrupted-download process relaunches; no reset/rebinding or adb UI fallback. Removed own route during cleanup; final list empty. Ports7364/7365 and owned processes stopped; builder7464/7465 untouched. Evidence docs/evidence/playback/android-authorized-retest.md.

**2026-11-08T02:52:44Z**

Closed on user acceptance, Nov 7: the user accepted the merged work and will report any issue they run into.
