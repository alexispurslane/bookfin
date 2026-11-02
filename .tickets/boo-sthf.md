---
id: boo-sthf
status: in_progress
deps: [boo-7o92, t0-dqxp, t0-60ea]
links: [t0-60ea, t0-dqxp, boo-6h8w, t7-msmk]
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

**2026-11-02T06:54:02Z**

Reviewed corrections integrated at 8ff61d4, preserving main real-Jellyfin auth and ebook fixes. Keep in_progress pending corrected Android interruption/Stop/signout/sleep observations and supported real-Jellyfin playback report acceptance. No full runtime acceptance or user acceptance inferred from review.

**2026-11-02T08:27:44Z**

Integrated Android acceptance from d9bc3a6 used this worktree own fresh core-only Jellyfin12.4.0 and generated AAC/EPUB only. Found native position/source and decoder-release defects; t0-dqxp contains five meaningful red regressions and small existing-adapter fixes. Final APK: native Pause/restored position95081ms, paused chapter seeking, actual file transition, normal focus recovery, interrupted Stop, interrupted signout, and five-minute interrupted sleep expiry observed. Sleep expiry stayed PAUSED7873ms when focus returned. Preceding corrected APK additionally proved fully disconnected playback/process restore and no old offline-session replay on reconnection; that offline run was not repeated after the last Pause-position correction. Real Jellyfin accepted start/progress/stop with source-relative ticks and204 responses, not only a stub. Detailed raw evidence/boundaries: docs/evidence/playback/integrated-android.md and integrated-observations.json. Final checks:199 Flutter tests, clean analysis, Android debug build,40 research tests,6 acceptance-tool tests,9 runner-authoritative live checks. t0-60ea retains discrete manual Pause during already-lost focus; physical-phone/credential-locked-screen/background soak unproven. No coverage/mutation. Own downloads removed/signout confirmed after restart, radios restored, own forward removed, both own servers exited, own device released without shutdown. Parent owns review/integration/closure; remains in_progress.

**2026-11-02T08:44:46Z**

Integrated reviewed Android evidence and parent F1 correction at2edad39. 200 app tests and clean analysis. Remaining native position runtime confirmation plus final corrected-build offline/reconnect and discrete interrupted manual Pause remain original acceptance. Added explicit native followup dependencies; no closure yet.

**2026-11-02T09:24:52Z**

Final bounded original acceptance evidence supplied from 03ac7f5, including actual Android on the exact final normal-app APK71c55e1d and a separate real-decoder test APK37311018 for discrete Pause while focus was already lost. Native retention, paused seeks including0, natural source transition, retained-position Play, fully disconnected playback/process restart/reconnect, and no obsolete report replay all observed.20 actual Jellyfin204 responses in the final normal-app interval. Exact artifacts, source hashes, chronology, runtime/model boundaries, test commands and cleanup are recorded in docs/evidence/playback/final-head-android.md and final-head-observations.json. All200 app tests and clean analysis; no coverage/mutation, physical phone, credential-lock, soak or full-sync claim. No application playback fix needed. t8-ld5q and t7-bzzg unchanged. Parent review/integration/acceptance/closure remain pending; no tickets closed.

**2026-11-02T09:31:54Z**

Final native acceptance integrated at7090471; both native correction followups close. Parent independently reran ten native tests and clean analysis; 200-test suite and Android observations remain builder execution evidence. Keep this ticket in_progress because credential-locked-screen controls remain unverified under its original controls acceptance. Physical-phone and soak limits also remain explicit. The integrated playback interface is ready for history development; that independent work need not wait for the remaining acceptance observation. No shared user acceptance is inferred.

**2026-11-02T11:39:46Z**

Bounded Android follow-up at72996e4: originally unsecured emulator allowed a temporary synthetic PIN through Settings, then cleanup restored Screen lock None and deviceLocked=0. Credential-locked playback controls were not reached: acceptance stopped before production sign-in after field-focus refusal and an expired-reference diagnostic retry. This does not establish unsupported lock controls or an application defect. No permission/credential bypass, no code change, no test APK, coverage or mutation work. Own servers/forward/binding cleaned; emulator left running. See docs/evidence/playback/personal-records-android.md and t7-msmk. Leave in_progress.

**2026-11-02T12:21:24Z**

Fresh attempt at756ae5f did not reach playback or credential setup. A malformed Settings activity argument and failed advised retry stopped acceptance under the device rule. This is operator error, not an app regression. No credential-locked control, interruption or native action acceptance was added. Normal main APK builds; all271 host tests, analyzer and SDK-link checks pass. Own services stopped and binding released without shutdown, radios/settings unchanged. See docs/evidence/playback/personal-records-fresh-attempt.md. Leave in_progress.

**2026-11-02T14:13:50Z**

Current-main normal APK82faf07d reached downloaded one-file M4B native PLAYING at24408ms, Pause at displayed00:49 and restored selection without autoplay after process restart. Real observer recorded one start and eight progress HTTP204 responses. No multi-file/offline/lock-screen/interrupt/reconnect or full-sync acceptance in this attempt. Later tool retry failure stopped acceptance; own cleanup complete. Evidence docs/evidence/playback/current-main-android.md. No source change, suite rerun or closure.
