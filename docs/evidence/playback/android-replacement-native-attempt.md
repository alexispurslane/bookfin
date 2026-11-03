# Android replacement and native listening attempt

Date: November 2, 2026. Recorded event times use UTC.
Parent source: `1f1b1c6`.
Primary ticket: `t8-ld5q`. Related tickets: `boo-sthf`, `boo-6h8w`, `t7-bzzg`, `t7-msmk`, and `t2-y0ce`.

Result: this attempt stopped before sign-in. No requested acceptance gate advanced.
Two consecutive device-command errors triggered the required stop rule.
The second error resulted from this worker reusing an expired screen reference.
It is not evidence of a Bookfin defect or of a second field-focus refusal.
No production code, tests, or toolchain changed in this lane.
No application data was deliberately edited or erased.
The parent owns integration and ticket closure.

## Verified candidate and ownership

An APK is an Android installation file. SHA-256 identifies its bytes.
The source comparison between `17c9e6b` and `1f1b1c6` found no differences in application, Android, assets, packages, dependency locks, or Nix sources.
The prior normal `lib/main.dart` ARM64 debug APK therefore remained an eligible candidate.
This worker independently read the installed package path and pulled its APK before any attempted field entry.
Both the installed copy and the prior build contained 100,151,103 bytes and matched this SHA-256:

`8e4f386e79a0446a9ae2c51f0f157d07d9953b4aa4cf5f23ed3c3957b5be534b`

The package was `dev.bookfin.bookfin` on `local` / `emulator-5554`.
No build or install was necessary. Host load averages were 10.35, 24.42, and 24.83 at the initial check.
System-wide free memory was 53 percent. No competing heavy test or build command started.
All fixture and Android readback commands ran through the existing pinned Nix development shells.

This worker read the product plan, ready tickets, relevant ticket dependencies, and prior listening and reader evidence.
Previously completed playback, bookmark, slider, EPUB, and appearance cases were not repeated.
No child, workflow, PR, coverage, mutation, toolchain installation, or shared-checkout reset occurred.

The worker acquired a new supported binding, `t3-b9718bd16302bb4fb7b69f4f`.
It did not reuse the released reader binding.
Opening Bookfin succeeded, and the initial screen contained empty sign-in fields and disabled account-only destinations.
T3 `device_screenshot` inspected that initial screen.
The initial allowed process readback returned the previously documented PID 11695.
This worker does not claim that the previous worker terminated it.

## Disposable fixture

Both ports 7364 and 7365 were free before startup.
This checkout started its own disposable Jellyfin 12.4.0 core on host loopback port 7364.
The existing fixture seeded two ordinary synthetic users and synthetic media.
The existing observer listened on host loopback port 7365.
This worker added only its own Android reverse route for port 7365.
No credentials were entered, no account authenticated in Bookfin, and no media downloaded or played.
No production account, private library, other fixture, or builder port 7464/7465 was changed.

## Device errors and stop

The first server-field action at `2026-11-02T23:58:01.879Z` returned:

```text
Error (COMMAND_FAILED): Field focus was refused
Hint: Retry with --debug and inspect diagnostics log for details.
Diagnostic ID: mvzx5wuv-3aa4bb0a
```

Instead of taking a fresh screen snapshot and following that advice, this worker had already submitted a second field action in the same shell command.
That username-field action at `2026-11-02T23:58:02.324Z` returned:

```text
Error (COMMAND_FAILED): Ref @e6 belongs to an expired ref frame — a device action since the snapshot invalidated it
Hint: The UI may have changed since these refs were issued, so they no longer represent current device state. Take a new snapshot before relying on or interacting with them.
Diagnostic ID: mvzx5x78-343cb8b4
```

The device did not dispatch the username entry. No password action was submitted.
The single advised debug retry was not performed before the second error. This is a process failure by this worker.
After the repeated error, this worker stopped acceptance rather than retrying field entry, acquiring another binding, or using an adb UI fallback.
Only cleanup followed. Both diagnostic logs were inspected without another device interaction.
The bounded public record retains the errors without private credentials or raw application preferences.

## Requested cases and evidence boundary

| Case | Result in this attempt | Remaining requirement |
| --- | --- | --- |
| Normal replacement-source confirmation and Cancel | Not reached | Observe the normal Android dialog and both choices. |
| Confirmed fresh start with old resume, history, and bookmarks retained | Not reached | Compare original and replacement recording records across actual playback. |
| Process restart and no silent remapping | Not reached | Relaunch the app and prove recording-scoped records remain separate. |
| Native notification and lock-screen controls | Not reached | Observe Android media controls and resulting persistent actions. |
| Native interruptions | Not reached | Exercise supported interruption cases and resulting persistent actions. |
| Real Jellyfin interrupted-download recovery | Not reached | Exercise the app against the real disposable server, not a synthetic range response. |
| Actual TalkBack | Not attempted | Existing host block `t2-u76g` remains. No workaround was attempted. |

The existing `t7-bzzg` safety boundary remains unchanged.
Real Jellyfin responses previously lacked a strong HTTP ETag, the server-provided identifier required for saved-prefix reuse.
This attempt neither relaxed that requirement nor decided whether a safe complete restart meets user acceptance.
There are no new successful normal-outcome screenshots or personal-record readbacks from this attempt.
No native reader security, sync, physical-phone, or interruption acceptance follows from package verification or cleanup.
No new product defect was established, so no duplicate product ticket was created.
The existing field-entry ticket records this blocked attempt and the operator error separately.

## Cleanup

The worker used its still-valid bound command to close the named Bookfin package before releasing the binding.
That cleanup command returned `Closed: t3-b9718bd16302bb4fb7b69f4f`.
An independent allowed `pidof dev.bookfin.bookfin` readback returned no process afterward.
This is evidence of named close followed by process absence for this attempt only.
It does not rewrite the earlier released-binding failure recorded in `t2-y0ce`.

| Owned state | Final observation |
| --- | --- |
| Bookfin account | Initially signed out. No sign-in action or credential entry occurred. |
| Download and personal records | No owned download or record created. No retained history or preference erased. |
| Named app process | No PID after bound named close. |
| Font scale | 1.0 before and after. |
| Airplane mode | 0 before and after. |
| Wi-Fi | 1 before and after. |
| Enabled accessibility services | Empty before and after. |
| Other settings | No settings, PIN, radio, appearance, TalkBack, or media override action performed. |
| Reverse routes | Own port-7365 route removed. Final list empty. |
| Jellyfin | Owned PID 54005 shut down through the authenticated fixture command. Command exited zero. |
| Observer | Owned PID 55108 stopped with SIGTERM. Command exited 143. |
| Fixture ports | No listeners after shutdown and recheck. |
| Binding | Released with `shutdown: false`. Emulator remains booted. |
| Build and test processes | None started. |

The private fixture runtime and pulled APK were removed after the public evidence audit.
The existing Nix shell references remain ignored under `.cache`.
No owned command remains running.
Any further Android acceptance attempt requires explicit renewed authorization after this stop.
