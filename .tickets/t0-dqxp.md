---
id: t0-dqxp
status: in_progress
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
