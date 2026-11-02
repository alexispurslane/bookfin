---
id: t0-dqxp
status: closed
deps: []
links: [boo-sthf]
created: 2026-11-02T07:24:44Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Keep native file identity coherent with position samples

Android acceptance against disposable Jellyfin observed a source transition report for the previous source at zero before its stop. LocalAudioEngine reads the delayed currentIndex stream getter alongside the newer playback-event position. Use one playback-event source identity for the position sample and prove it with a regression plus real Android file transitions.


## Notes

**2026-11-02T08:27:44Z**

Five meaningful red regressions reproduced delayed index/source mismatch, intermediate cross-file seek samples, loading zero placeholders, confirmed paused seeks hidden by filtering, and zero position during decoder release. Fixed only LocalAudioEngine: coherent playback-event source identity, suppression during seek/release, unconfirmed idle/loading filtering, explicit confirmed paused seek sample, and retained Pause position while stop still revokes recovery. All nine focused native tests and199 full Flutter tests pass, analysis clean, final APK builds. Actual final Android native Pause restored exactly95081ms, paused seeks updated without autoplay, real Jellyfin natural boundary stopped first source1799530000 ticks then started second850000 ticks with204 responses. Normal interruption recovery and interrupted Stop/signout/sleep-expiry suppression observed. Evidence: docs/evidence/playback/integrated-android.md. Parent review and integration pending; do not close.


## Parent correction: Pause during decoder reactivation

The review regression confirmed that Pause could publish an unconfirmed loading source/zero. LocalAudioEngine now has one confirmation rule shared by publication and Pause. It retains the last confirmed sample across loading, cancels interruption recovery with decoder Stop, and restores the confirmed decoder source/time if release changed it. A regression first failed and now verifies Pause during loading, subsequent Play at the retained position, and legitimate seeking to zero. New loads clear retained confirmation.

All 200 application tests pass; analysis is clean and changed Dart files are formatted through Nix. These are host tests, not a repeat of Android observations. The previously recorded native patch hash describes the earlier observed build; this correction has not yet been inspected on Android. Final-build offline repeat and discrete manual Pause during lost focus remain open.

**2026-11-02T09:24:52Z**

Bounded final-head follow-up from 03ac7f5 observed parent correction 2edad39 on a freshly rebuilt normal Android APK, SHA-256 71c55e1dfbfeeea00b5dbdd17430ac103ad4b36f57964508245d427f4ceef306; installed APK bytes matched. Native Pause and process restoration retained exactly19929ms, paused seeks accepted0/90000ms and second-source zero, retained-position Play worked, and a natural boundary stopped first source1798300000 ticks then started second210000 ticks with actual Jellyfin204 responses. Fully disconnected playback and process restoration repeated on this exact final artifact; restored242186ms versus last native242387ms, then offline Play advanced274227ms. Reconnect left report count37 unchanged; explicit Play sent fresh second-source945970000 ticks. No concrete correction regression found and no application playback source changed. Evidence: docs/evidence/playback/final-head-android.md and final-head-observations.json. All200 app tests,10 native unit tests, real-decoder integration test, analysis, final build pass. Remains in_progress for parent review/integration/closure.

**2026-11-02T09:31:54Z**

Parent reviewed and integrated 7090471. Correctness and design pass for the test/build-only follow-up; source hashes match the integrated native correction. Ten native tests and analyzer independently pass on main through Nix. Final APK observations cover Pause retention, legitimate zero seek, transitions, disconnected restart and reconnection. Exact loading-window schedule remains deterministic unit evidence. This closes this correction, not user or release acceptance.
