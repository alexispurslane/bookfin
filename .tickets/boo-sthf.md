---
id: boo-sthf
status: in_progress
deps: [boo-7o92]
links: []
created: 2026-11-01T21:37:34Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Deliver offline playback chapters and Jellyfin progress

Build the first complete download-to-listen path, native background playback, media controls, file/chapter mapping, speed, sleep timer, and durable resume.

## Design

docs/plans/bookfin.md

## Acceptance Criteria

Play a downloaded multi-file book offline. Resume after restart. Handle audio focus and lock-screen controls. Correctly report supported progress to Jellyfin without replaying old live-session events.


## Notes

**2026-11-02T04:54:59Z**

Starting implementation from integrated verified downloads; real localFile boundary and shared media policy are ready. Production playback, chapters, background/lock-screen controls, and durable resume follow the approved plan. Sync research remains separate.

**2026-11-02T05:35:06Z**

Core local playback and real native-control wiring are implemented. Red-green tests found and fixed restoration-command ordering, sign-out during source verification, selected-book metadata refresh, and stop-state/native-command consistency. Source-revision recovery remains deliberately unresolved and is recorded in a new epic child ticket; original resume records are retained and never silently applied to a replacement. Android runtime acceptance is underway using only a disposable loopback fixture and locally generated playable WAV files.

**2026-11-02T06:23:42Z**

Implementation ready for parent review/integration; ticket remains in_progress. Final pinned-Nix checks: all 180 app tests pass (31 playback), analysis clean, Android debug APK and JavaScript web release built, SDK-link checks pass, 15 Dart files format clean, diff whitespace clean. Android emulator acceptance used generated 90s/120s PCM WAVs and disposable loopback fixtures only: ordered-file transition/report IDs, offline chapters, 1.5x speed, native notification pause, exact -15s/+45s hardware jumps, completion/chapter paused-state regression, transient call focus loss/recovery, background playback, sleep on/off, and forced offline relaunch while actually playing. Before relaunch native recorded-time position was 156149ms; paused restore was 157051ms (second source 67051ms), no autoplay. Evidence and limits: docs/evidence/playback/acceptance.md. Physical phone, credential-locked screen, real Jellyfin deployment, and background timer soak remain unproven. t8-ld5q records the unresolved changed-source recovery decision; old positions are retained/refused, not reconciled. Downstream history/bookmarks must use the Playback owner and typed AudioPosition described in docs/playback.md. No reader/history sync or coverage/mutation work. Fixture stopped, files removed via UI, signed out, Wi-Fi/mobile restored, own forwards removed and own device session released without shutdown. Parent alone closes after integration.


## Parent review corrections

R1: owner-requested native pause uses the decoder stop operation to revoke pending interruption recovery even when already paused, retaining source selection. The focused adapter regression models the pinned dependency behavior; corrected Android interruption behavior has not yet been re-observed.

R2: saves require successful account restoration; account changes clear that readiness before any new save, failed reads do not authorize writes, and flush waits for restoration with a generation check. R3: failed and retired reporting sessions invalidate queued progress; intentional final stops remain distinct, and old failures do not cancel a newer session. R4/R5: relative jumps compute their target inside the serialized command and use source-relative movement when total duration is unavailable. The mini-player book title now uses Source Serif 4.

Eight regression tests meaningfully failed before these corrections. A further account-switch test checks old queued progress is discarded while final stop and new start retain their proper credentials. All 189 application tests pass and the Android debug build passes through the pinned shell. No corrected-build Android UI, physical phone, real Jellyfin playback, timer soak, coverage or mutation proof is claimed. Independent correction review remains pending.
