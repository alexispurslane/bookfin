# Fresh-install Android acceptance, November 3, 2026

This lane started from `b186860`. It used only the new disposable Android device.
It completed the runtime checks that provisioning blocked in `fresh-install/README.md`.
No child, production edit, rebuild, broader hardening, publication, or ticket closure occurred.

## Artifact and clean installation

An APK is an Android installation file. `artifact.json` records the exact normal APK and source archive paths.
The source commit was `d8e1021fef2be69291d135594a45d556570c235f`.
The artifact, source archive, and unchanged plugin were read-only throughout this lane.

| Artifact | SHA-256 |
| --- | --- |
| Normal ARM64 debug APK, also read back from the installed package | `8b31c7448f746226453d4677f944c9ba4f5668f657bba8015f94973372744e09` |
| Source archive | `3dd0c18fb2cdc3b94e8831f12b4ef92d573bccd73392a626b3c46de1dae45f60` |
| Bookfin Storage 0.1.1.0 package | `3b0de5ca1df39baf67c786079898b1ee3b0b09d3bdb86d00ece8a7f5731a9105` |
| Bundled English OCR model | `7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2` |

T3 opened host `local`, device `emulator-5556`, named `bookfin-accept-20261103-db111f95`.
This lane obtained its own bound command. It did not reuse the parent's command.
Every app launch, input, setting change, and screenshot used that exact bound command.
T3 `device_screenshot` also inspected the screen. No alternative device engine ran.

`preinstall.txt` recorded no installed Bookfin package and absent private/external application directories.
Normal `adb install` then succeeded. No uninstall, reset, preloaded private model, or private-row write occurred.
`pre-ocr-inventory.txt` recorded only initial application support files after first launch.
`before-first-ocr.json` recorded zero personal actions, two downloaded originals, and no private model or OCR cache.
An OCR cache is saved recognized page text. The English model was bundled inside the verified APK.

## Fixture and offline conditions

The owned loopback service ran real Jellyfin 12.4.0 with the unchanged Storage package.
It exposed two ordinary PDF originals without fabricated `Container` or `MediaSources` metadata.
Generated credentials stayed private. No public server or proxy was started.

`fixture.py` reused the existing scan generator with this lane's paths and a single-column image layout.
The English first page contained 11 image draws, with no PDF text layer.
Its second page was genuinely blank. Both pages of the separate blank original had no drawing commands.
`corpus.json` records exact original sizes and hashes. Its single-column metadata was corrected before final audit.
The original dense-generator metadata had incorrectly described this adapted fixture as 22 draws.

Ordinary sign-in and download preceded disconnection. The reader was not opened online first.
Media was muted through Android's volume control before any reader action and remained muted.
Airplane mode was on, Wi-Fi and mobile data were off, and the owned USB reverse route was removed.
The empty route inventory is `offline-routes.txt`; radio values are in `before-first-ocr.json`.
The first reader snapshot showed active recognition under those conditions.
No route or radio change occurred until after the offline reading, restart, and pending-action captures.

## Observed results

OCR means recognizing text from page images. This lane exercised bundled English OCR, not multilingual recognition.
A pending action is a durable local personal-record change not yet acknowledged through the real plugin.
An action identity is its stable replica-and-sequence name; its payload is the exact encoded personal record.

| Check | Result | Evidence |
| --- | --- | --- |
| Fresh first OCR fully offline | Passed; active recognition completed and supplied English text without a prior private model/cache | `before-first-ocr.json`, `first-offline-reader.txt`, `first-offline-result.txt`, `bundled-model.json` |
| Reflow | Passed; recognized English appeared as readable text | `reflow.txt`, `reflow.png` |
| Search | Passed; `garden` returned recognized source-page results and selecting a result moved the reading place | `search-results-complete.txt`, `search-place.txt` |
| Original access | Passed; original source image and controls remained available after reflow/search | `original-after.txt` |
| Saved place and bookmark | Passed; stored character 611 and its Unicode bookmark survived offline process restart and bookmark invocation | `unicode-pending.json`, `disconnected-relaunched.json`, `bookmark-restore-after.txt`, `cache-reused.json` |
| Cached reopen | Passed; cache path, size, hash, and modification time were unchanged after offline restart/reopen | `first-ocr-active.json`, `cache-reused.json`, `cached-reflow-after.txt` |
| Genuine blank fallback | Passed for the English book's second page and the separate blank original; original-page access remained available | `source-blank-after.txt`, `genuine-blank-complete.txt`, `genuine-blank-original-after.txt` |
| Durable Unicode pending | Passed; five exact actions retained their identities, payload hashes, contents, and pending flags through close/relaunch while disconnected | `unicode-pending.json`, `disconnected-closed.json`, `disconnected-relaunched.json` |
| Explicit initial upload | Passed; eight ordinary offline actions were absent remotely, then acknowledged with exact plugin readback | `all-offline-pending.json`, `all-offline-server.json`, `explicit-synced.json`, `explicit-server.json` |
| Repeated sync and acknowledged restart | Passed; eight acknowledged actions stayed stable and repeated sync left the remote object set unchanged | `repeated-synced.json`, `repeated-server.json`, `synced-restarted.json` |
| Account-owned originals/cache | Passed; Bob could not open Alice's download/cache, then ordinary download and fresh offline recognition created Bob's own cache | `bob-no-original-after.txt`, `bob-downloaded-before-ocr.json`, `bob-first-ocr-after.txt`, `bob-cache.json` |
| Account-owned bookmarks | Passed; Bob saw no Alice bookmark; Alice's Unicode bookmark and reflow returned after ordinary sign-in | `bob-bookmarks-after.txt`, `alice-return-bookmarks-after.txt`, `alice-return-reflow-after.txt` |
| Account-owned removal | Passed; ordinary removal deleted Bob's original/cache and preserved Alice's cache exactly | `bob-removed.json`, `bob-cache.json` |
| Final record safety | Passed; all ten retained actions matched real per-account plugin readback and none remained pending | `final-retained.json`, `final-alice-server.json`, `final-bob-server.json`, `audit.json` |

The title was `Fresh “Café” 中文 🐟`. The note was `Déjà vu — ‘naïve’ 中文 🐟`.
The five initial pending actions used replica `4dc7af887b1c059661dc7f3cec7b126d19c662f1`, sequences 1 through 5.
The remaining three offline actions followed ordinary original-page and blank-page navigation.
The first explicit upload therefore contained sequences 1 through 8, not just the bookmark edits.
Readback matched identities, payload SHA-256 values, values, replica sequence, and causal contexts.
Causal context records which earlier actions a change had observed. No server acknowledgment was invented.

## Explicit-sync timing and later actions

The app was relaunched while disconnected before restoring the owned route.
The disconnected launch could not upload; the supported periodic interval was 30 seconds.
No radio or lifecycle change occurred between route restoration and the explicit button.

| Account | Route restored after launch-command start | Button command completed after launch-command start | Uploaded actions |
| --- | --- | --- | --- |
| Alice, initial batch | 8.393 seconds | 11.953 seconds | 8 |
| Bob, owned reading place | 9.693 seconds | 11.863 seconds | 1 |

Full unrounded timestamps are in `explicit-timing.json` and `bob-explicit-timing.json`.
Both complete button commands finished before the earliest possible periodic timer boundary.
The button's fresh complete snapshot and synced result are retained for each account.
Bob's plugin was empty before his button and contained his exact action afterward.

Returning to Alice and invoking her bookmark created one additional reading-place action.
It was acknowledged during connected cleanup. That later acknowledgment is not attributed to the initial explicit button.
Final readback contained nine Alice actions and one Bob action. The original eight Alice actions stayed unchanged.

Lost-acknowledgment acceptance was not exercised. The existing Android proxy gates downloads, not personal-record acknowledgment responses.
The older research transport's synthetic timeout is not an unchanged normal-app runtime gate.
No new proxy implementation or production change was introduced merely to claim this optional check.

## Tool errors and limits

`tool-errors.json` records all eight device-command errors and their successful single advised recoveries.
These included field-focus refusals, unsettled targets, one invalid settings shortcut, and one failed relaunch.
No retry failed. No binding was replaced and no alternate engine, adb UI action, or settings bypass was used.
Acceptance execution batches stopped on failure and resumed only after the failed step was addressed.
One initial evidence-helper batch lacked a failure guard and continued only to read `help close` after a parser error.
No device-state action followed that parser error before its correction.

One stale planned reference opened the correction sheet after radio changes changed the full snapshot numbering.
The sheet was canceled without saving. The subsequent pre-OCR baseline contained zero personal actions.
Later inputs used current complete snapshots; `ui.py` selected exactly one label and dispatched its fresh reference.

Three evidence-helper mistakes were corrected: indentation matching, an exploratory missing JSON key, and Bob's library readback retaining Alice's user ID.
The failed Bob readback returned HTTP 403 and produced no accepted report. The corrected helper used Bob's own account throughout.
These were evidence-collection errors, not production mutations or fabricated success.

Existing defect `t8-oitu` reproduced: a PDF without a local original also displayed an EPUB-specific unopened-reader message.
No new production defect was found. UI coherence `boo-4ixi` remains deferred.
Native recognition callback ordering was not traced. This report makes no new native-drain or late-callback claim.
Latency, peak memory, arbitrary reading order, other OCR languages, private-library compatibility, and broad hardening were not measured here.

The retained `local/emulator-5554` was never opened or operated.
Its earlier 79 actions and 28 pending actions were not freshly measured or changed by this lane.
Original-account recovery remains separately blocked in `t2-00a4`; no broad backup search was repeated.
Fresh-account success cannot recover the original 28 actions, and no account/server identity was fabricated.

## Cleanup and audit

All owned downloads were removed through ordinary account-specific controls.
The app was signed out and closed. Final radios were airplane/Wi-Fi/mobile-data `0/1/1`; media stayed muted.
The final database passed SQLite integrity and retained ten acknowledged actions, with zero pending.
No downloaded original or OCR cache remained. The bundled private English model remained installed.

The owned USB route was removed. Both account readbacks and the zero-pending audit preceded server removal.
The owned service stopped, its private server identity/credentials were removed, and its copied installed APK was deleted.
No sole pending-action recovery path was removed because no action remained pending on this disposable target.
`host-cleanup.json` records stopped owned processes and closed loopback ports 7364/7365.
The generated-password/token scan found no match in public evidence. No raw database or token was committed.
Four text captures had a redundant final blank line removed; no content line was changed.
`evidence-hashes.sha256` records the final sanitized evidence bytes.

T3 released the owned target with `shutdown:true`. Final discovery showed the owned AVD unbooted and no open thread devices.
Its saved AVD and ten acknowledged records were not deleted. The original AVD remained listed as booted.
No physical phone action occurred.

The reproducible evidence audit runs through the pinned project shell:

```sh
nix develop --command python3 tool/evidence/reader/integrated/20261103/fresh-booted/audit.py
```

It audits captured evidence, not live device state after shutdown. No full host test suite was needed for this unchanged APK lane.
The verified APK/source paths in `artifact.json` are the handoff for the parent's personal-phone trial, not release approval.
