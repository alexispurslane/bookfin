# Remaining normal-app Android acceptance, November 3, 2026

The user explicitly authorized execution, not a plan. This exclusive device lane
installed and exercised the normal application. It then reached the required stop
after a snapshot failure and one failed advised retry. Most remaining acceptance
criteria are still blocked. This is not a completed acceptance pass.

Source is `71af2886e722b7366d4d335622e55e18a151a3e0`; evidence base is
`772d8a50b64cafa99baf534f8f74274a9882126c`. Evidence is in
`tool/evidence/reader/integrated/20261103/remaining/`. No child, competing device
task, production edit, rebuild, broad test run, hardening, publication, or ticket
closure occurred. Previously accepted KF8 saved passages were not repeated.

## Installation and ordinary inputs

An APK is an Android application package. Its SHA-256 hash identifies its bytes.
The normal APK was read from the existing read-only main artifact directory and
installed in place with `adb install -r`. Installation succeeded. Readback of the
installed APK matches the normal artifact exactly:
`129a9a82a338a2e7b5cf1abd154c729866a328295c241063fabd26e38353c270`.
The companion was replaced without reset, uninstall, or private database writes.
All 69 prior action identities, payload hashes, and pending flags survived exactly.

OCR means recognizing text from page images. A new ordinary Jellyfin library
served two actual PDF originals, downloaded through the normal application:

| Original | Input | SHA-256 |
| --- | --- | --- |
| Acceptance dense English | 22 unchanged English image draws, two columns; second page truly blank | `c931753b6c88b4c2e5a464488297c4bc6bf19604f69500d730ba2b908e204da1` |
| Acceptance blank | Two genuinely blank pages, no drawing commands or PDF text layer | `fe5149e7d965a3229af11e3e38f63e3957d10d7718c4a42d9749a4ab2a4c9744` |

The dense source page measures 1600 by 4000 PDF points. A PDF point is 1/72 inch
in the document's coordinate system. It contains 814 reference words. This is a
new challenging multi-column fixture, not a fake recognition engine or injected
cache. The existing pinned English image hash is in `corpus.json`.
The server returned ordinary Book responses without `Container` or `MediaSources`.

Jellyfin was 12.4.0. The actual unchanged Bookfin Storage plugin package hash was
`3b0de5ca1df39baf67c786079898b1ee3b0b09d3bdb86d00ece8a7f5731a9105`.
Its generated ordinary accounts and service listened only on loopback.
No credential or token was printed or committed.

## Observed active work and required stop

Host `local`, device `emulator-5554`, used its own T3 binding. Every launch,
input, settings action, and screenshot used the returned bound command.
T3 screen inspection was also used before sign-in. Complete snapshots preceded
reference use. Field entry used exact field references and succeeded.

Radio settings were changed to airplane on, Wi-Fi off, mobile data off. The
normal reader opened the downloaded dense original. The next complete snapshot
showed `Recognizing English text…`, `Cancel recognition`, and the original image.
The bound command dispatched one Cancel to that exact fresh button reference.
The full snapshot completed at 19:04:03.199 UTC; the dispatch command started at
19:04:03.200 UTC. This bounds operator delay, not native recognition completion:
there is no independent proof that native work was still active when input arrived.
Command settling could not inspect the application, despite reporting that the
tap itself succeeded. The following complete snapshot failed:

```text
Error (COMMAND_FAILED): Android snapshot helper returned insufficient foreground app content
```

The first diagnostic is `mw123qnc-f55b5356`, at 19:04:04 UTC. The tool advised
retrying after the UI stabilized. The one fresh complete snapshot retry failed
with the same error at 19:04:28 UTC, diagnostic `mw1248f2-2610843c`.
Diagnostics identify Bookfin as foreground but report only one meaningful app
node, below the helper's threshold of two. No alternate engine, binding, UI
fallback, screenshot, input, launch, or settings command followed that failure.
The binding was subsequently released without shutdown.
`binding-release.json` records the successful `device_close` call with
`shutdown:false`. The tool returned an empty success object.

The process still existed and the read-only crash buffer was empty. Neither fact
establishes a healthy reader, successful cancellation, or the cause of lost
inspection. This is an inspection blocker, not an established Bookfin crash.
Ticket `t0-ys9g` records the exact reproduction and cleanup still required.

## Acceptance results

| Criterion | Result | Bound of evidence |
| --- | --- | --- |
| Normal in-place update preserves retained records | Pass | All 69 prior identities, exact payload hashes, and pending flags unchanged |
| Larger ordinary scan reaches active recognition | Pass | Fresh full snapshot shows active status, Cancel, and original image |
| Active Cancel input | Observed, not full acceptance | Tap dispatched immediately after active snapshot; completed cancellation cannot be inspected |
| Cancellation drains native work and supports retry | Blocked | Snapshot failure prevented retry and result inspection; no hard native-interruption claim |
| Active departure rejects late results | Blocked | Never attempted after required stop |
| Genuine blank-page original fallback | Blocked | Actual blank input downloaded, but never opened |
| Cache reuse/removal/source/account ownership | Blocked | No OCR page cache in read-only stop inventory; no ownership sequence completed |
| Durable nonzero bookmark/resume through fallback | Blocked | Not attempted; earlier accepted nonzero OCR and KF8 results are unchanged |
| Explicit Account > Sync now with offline Unicode actions | Blocked | No Unicode bookmark or explicit retry reached; the sole new action uploaded automatically |
| Original account recovery | Not established | Eight conventional existing backups checked read-only; no original pending account match |
| Fresh-install offline OCR on a separate device/profile | Unavailable | T3 lists only the retained emulator; no separate supported disposable target exposed |
| Physical phone, two-device, TalkBack, legal approval | Not tested | Cannot be inferred from this emulator lane |
| Approved PDF body font | Known failure remains | Existing `te-rtok`; no production edit in this lane |

T3 discovery does not prove that the host can never create another target. It
establishes only that this lane had no separate supported disposable Android
device/profile available. The retained emulator was never wiped or uninstalled.

## Records, real plugin readback, and radio-isolation limit

An action is one retained personal-record change. Pending means the device has
not acknowledged its upload. Baseline contains 69 actions, including the original
28 pending actions. The reader created one new ordinary resume action. A real
read-only capture showed it pending: 70 retained, 29 pending.

Later, the real unchanged plugin contained that exact action, including its
payload hash, replica/sequence identity, causal context, and value. The device
then held 70 retained and 28 pending actions. Only the new action was acknowledged;
all 69 prior actions remained byte-hash-identical with unchanged pending flags.
No Unicode content, explicit-retry causality, restart durability, or recovery of
the original account follows from this single automatic upload.

The owned `adb reverse` loopback route was still present during the radio-off
reading attempt. That route forwards the emulator's local port to the host's
local fixture without requiring emulator Wi-Fi or mobile data. Its actual upload
shows why radio-off settings alone did not create a disconnected sync test.
This lane makes no new fully disconnected OCR or offline-sync acceptance claim.
Ticket `t0-yy48` requires route isolation before the next pending-action test.
No hidden row mutation should substitute for that supported fixture sequencing.

The read-only backup inventory searched existing conventional sync/plugin
fixture directories under main and local T3 worktrees. Eight account-bearing
fixtures were available; none matched the original pending account identities.
This is a bounded local search, not proof that no external backup exists.
No replacement server identity was fabricated. `t2-00a4` remains unresolved.

## Cleanup and remaining device state

The required stop prevented UI cleanup. No device action bypassed it.

| Item | Final observed state |
| --- | --- |
| Application | Normal APK installed; signed-in state not cleared; process still present |
| Owned downloads | Two originals remain, exact hashes match corpus |
| OCR cache | No derived page-cache file observed; bundled private model remains |
| Network | Airplane/Wi-Fi/mobile-data `1/0/0`; original `0/1/1` not restored |
| Media | Muted in every read-only capture |
| System text size | Large, unchanged |
| Owned server/controller | Both stopped; ports 7364 and 7365 free |
| Owned route | Removed |
| Host private data | Owned fixture, credentials, raw logs, temporary captures, and database copies removed |
| Pending fixture recovery backup | Not required for the new account: its sole action exactly matches plugin and none remain pending |

The original 28 pending actions are untouched, not deleted or acknowledged.
Cleanup did not remove another fixture's backup. Sign-out, application close,
download removal, and restoration to `0/1/1` still require a separately authorized
device lane. Binding release does not perform any of those operations.

## Verification

Commands used the pinned project Nix development shell; the owned Jellyfin fixture
used the pinned sync research shell. No host full suite was repeated for evidence.
The repeatable host-only audit compares all captures, prior-action preservation,
the exact real plugin action, installed artifact identity, retained original bytes,
helper failure/retry ordering, and host cleanup. It does not drive the device or
turn an uninspectable result into an acceptance pass.

```sh
nix develop --command python3 tool/evidence/reader/integrated/20261103/remaining/audit.py
```

The audit and `git diff --check` pass. Tickets `boo-suhu`, `t2-00a4`, and `t7-msmk`
receive bounded notes. No ticket is closed. No acceptance result relies on tap
intent alone. The requested remaining normal-app acceptance is incomplete.
