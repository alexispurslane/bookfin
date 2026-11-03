---
id: t2-y0ce
status: open
deps: []
links: [boo-ohud]
created: 2026-11-02T23:45:24Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Clarify bound Android session close and application process cleanup

Observed November 2, 2026 during boo-ohud acceptance on local/emulator-5554. Bound agent-device close reported Closed: t3-0687f49c0b8d6053d5bd7d54, then device_close(shutdown:false) released the binding. Subsequent allowed adb readback pidof dev.bookfin.bookfin still returned the prior process11695. The app was already signed out, own download removed, settings restored, and fixture servers/routes stopped. A single explicit close dev.bookfin.bookfin attempt through the same returned executable failed exit127 with No such file or directory because release removed the executable. No binding reset or adb UI fallback. Need a supported sequence that closes the named app before release and verifies its process state; do not claim session-close success proves app-process termination. Evidence: docs/evidence/reader/android-remaining.md and tool/evidence/reader/android-remaining/cleanup.json.

## Acceptance Criteria

Supported bound named-app close confirms Bookfin no longer runs before device release. Restore only owned state; no binding-reset workaround or adb UI fallback. Distinguish session release from app termination and retain exact readback evidence.

## Notes

**2026-11-03T00:00:39Z**

Independent authorized listening attempt from1f1b1c6 observed initial existingPID11695. During own cleanup, before device release, fresh still-valid bound agent-device close dev.bookfin.bookfin returned Closed:t3-b9718bd16302bb4fb7b69f4f and allowed pidof readback returned no PID. Released shutdown:false afterward. This proves the supported named-close-before-release sequence for this run, not successful termination by the prior released reader binding. Evidence docs/evidence/playback/android-replacement-native-attempt.md and tool/evidence/playback/android-replacement-native/runtime.json. Parent owns assessment/closure.

**2026-11-03T00:54:04Z**

Fresh fc4531c acceptance independently repeated supported sequence: signed out and removed own media, bound close dev.bookfin.bookfin returned Closed:t3-42ca2fc685f8e741abe863b6, two allowed PID readbacks showed no Bookfin process BEFORE device_close(shutdown:false). Own fixture/services/routes also stopped before release. This verifies named-app close rather than assuming session release terminates the process. Evidence docs/evidence/playback/android-authorized-retest.md. Parent owns closure.
