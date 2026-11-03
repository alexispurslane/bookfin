# Resumed normal Android acceptance, November 3, 2026

This lane started from main `e4baaf9`. It used the user's renewed authorization
and exclusive Android device lane. No child agent ran. No production file,
product test, plugin, toolchain, or package was changed or rebuilt.

## Artifact and device

An APK is an Android installation file.
The exact normal ARM64 debug APK from clean source
`d8e1021fef2be69291d135594a45d556570c235f` was installed in place with `adb install -r`.
Installation succeeded without uninstalling, resetting, or changing private rows.
Both the source artifact and the installed APK matched SHA-256
`8b31c7448f746226453d4677f944c9ba4f5668f657bba8015f94973372744e09`.
The source archive matched
`3dd0c18fb2cdc3b94e8831f12b4ef92d573bccd73392a626b3c46de1dae45f60`.
The artifact and source archive were read-only. `artifact.json` records their
identity; `artifact-hashes.txt` records the initial host hashes.

The target was T3 host `local`, device `emulator-5554`, named `bookfin-api36`.
This lane opened its own binding. Every app, input, setting, and screenshot action
used that binding's exact `agent-device` command. T3 `device_screenshot` inspected
the screen. No adb UI command, alternate engine, or alternate binding was used.
Adb was used for installation, read-only diagnostics, and the owned loopback route.
T3 discovery exposed only this retained emulator, not a separate disposable Android
target. The emulator was never wiped. System text size remained large.

## Ordinary fixture

The owned loopback server was real Jellyfin 12.4.0. It used the unchanged Storage
0.1.1.0 package with SHA-256
`3b0de5ca1df39baf67c786079898b1ee3b0b09d3bdb86d00ece8a7f5731a9105`.
It exposed ordinary book originals, without fabricated `Container` or `MediaSources`
metadata. Generated credentials stayed private. No public server was exposed.

`fixture.py` reused the prior dense/blank generator with this lane's own paths.
The dense first page drew the English image 22 times in two columns. Its second
page was genuinely blank. The separate blank fixture also had no page drawing
commands. `add_single_column.py` reused the same generator with 11 image draws in
one column. This supplied reliable English order for completed retry and cache
checks without changing the challenging dense fixture. Exact hashes and sizes
are in `corpus.json` and `single-column.json`.

## Observed results

Active status below means that fresh complete inspection showed
`Recognizing English text…` and `Cancel recognition` before input. It does not
mean that Android recognition execution was traced. OCR converts page images to
text. An OCR cache is saved recognized page text owned by a local download.

| Case | Result | Evidence |
| --- | --- | --- |
| Active dense Cancel | Pass: active status and Cancel were visible before dispatch; cancellation left the original image and usable reader controls, including known page 1 with no total | `dense-active-cancel-before.txt`, `dense-active-cancel-after.txt`, `cancel.png` |
| Dense retry | Pass for recovery to a safe fallback: recognition completed with the expected unreliable-order explanation; this is not successful dense text reflow | `dense-retry-after.txt`, `retry-observed.txt` |
| Active single-column Cancel and retry | Pass: Cancel preserved controls and the original; immediate retry later supplied recognized English for reflow | `single-cancel-before.txt`, `single-cancel-after.txt`, `single-retry-after.txt`, `single-reflow-after.txt`, `retry-reflow.png` |
| Genuine blank fallback and original access | Pass: no English text was recognized, the original blank page remained available, and the original-page control worked | `blank-fallback-observed.txt`, `blank-original-after.txt`, `blank.png` |
| Active reader departure | Pass for visible departure: both dense reading and single-column bookmark restoration showed active status before Back, then book details | `active-departure-before.txt`, `active-departure-after.txt`, `single-active-departure-before.txt`, `single-active-departure-after.txt` |
| Post-departure screen stability | Pass within the recorded window: book details remained visible; no later screen replacement occurred | `single-departure-late-screen.txt` |
| Exact native drain ordering and late-callback rejection | Unverified: no native invocation/return/disposal trace was added; a successful-page cache appeared during the single-column departure command | Timing limits below |
| Cached reopen | Pass: the same character-574 reading place reopened in reflow; the cache's path, bytes, hash, and modification time were unchanged | `single-cache-reflow-after.txt`, `single-bookmarked.json`, `single-cache-reused.json` |
| Ordinary cache removal and source ownership | Pass: removing the single-column edition removed its original, manifest, and OCR cache; both other originals stayed byte-identical | `single-removal-complete.json` |
| Nonzero resume and bookmark through uncached Cancel | Pass: ordinary redownload restored the same source; Cancel before text completion retained the page-1 character-574 resume and bookmark payloads; bookmark restore was invoked and later reflow recovered the saved place | `nonzero-fallback.json`, `nonzero-fallback.png`, `nonzero-bookmark-restore-after.txt`, `nonzero-recovered.json`, `nonzero-recovered.png` |
| Page-two fallback durability | Pass across reader close/reopen: the dense book reopened at its saved blank page 2; its Unicode bookmark remained durable through process relaunch and plugin readback | `saved-fallback-reopen-after.txt`, `unicode-sync-server-after.json` |
| Route-isolated Unicode actions and explicit Sync now | Pass: five genuinely pending ordinary actions were acknowledged by the real plugin after the explicit button dispatch | Sync evidence below |
| Original account's 28 pending actions | Not recovered or acknowledged; all remained exactly preserved | `final-retained.json`, `audit.json` |

Chinese characters and the fish emoji were bookmark content, not OCR inputs.
English remains the only supported recognition language. These observations do
not establish arbitrary table or multicolumn reading order.

## Timing limits

Native drain ordering means the running Android recognition finishes before a
retry invokes recognition. Late-callback rejection means an old recognition
result cannot change a canceled or departed reader's screen, position, or selected
cache after that reader loses ownership.

Visible active status followed by a successful Cancel or Back dispatch is not a
trace of native work. This lane does not strengthen the reviewed host test's
immediate-call-count assertion into independent proof of native serialization.

The single-column Back command ran from Unix time `1793738167.782509` through
`1793738169.065247`. Its newly selected cache had modification time `1793738168`,
with only one-second filesystem resolution. Native completion before widget
disposal and late publication cannot be distinguished from these observations.
The first post-command capture already contained that cache. The later capture,
about 125 seconds after command completion, had the exact same cache metadata
and still showed book details. No Android pass for exact late-callback rejection
or native-drain ordering follows. The dense retry did not select reliable text,
so its lack of a cache does not prove late-result rejection either.

## Route isolation and real Unicode readback

An action is one durable personal-record change. Pending means that its upload
has not been acknowledged on the device. The baseline contained 70 actions,
including the original 28 pending actions. All 70 identities, exact payload
hashes, source identities within those payloads, causal data, and pending flags
matched the final capture and every intermediate record capture.
A replica identifies one local writer. Its sequence is that writer's action
counter. Causal context records the action counters known when a change was made.

Before offline actions, this lane removed only its owned `adb reverse tcp:7364`
route. It also set airplane/Wi-Fi/mobile-data to `1/0/0`. The route inventories
were empty. This fixes the prior fixture-sequencing error: radio settings alone
were not treated as disconnection.

The ordinary reader saved this page-two bookmark while disconnected:

- Title: `“Café” 中文 🐟`.
- Note: `Déjà vu — ‘naïve’ 中文 🐟`.
- Position: dense original, source page 2, character 0.

The device held 75 retained actions and 33 pending actions before explicit sync.
The five new-account actions were all pending. The real plugin contained no
objects. The app was relaunched while the route remained disconnected. Its
Account screen exposed the enabled Sync now button. The route was restored
8.050 seconds after relaunch began; the fresh-snapshot button dispatch happened
before the 30-second background interval. No radio or lifecycle change occurred
between route restoration and the button. The visible result was
`Personal records are synced.`

After the button, the same 75 actions remained, with only the original 28 pending.
The real unchanged plugin contained those exact five actions. Identity, payload
hash, replica, sequence, causal context, position, title, and note all matched.
See `unicode-sync-before.json`, `unicode-sync-server-before.json`,
`unicode-sync-after.json`, `unicode-sync-server-after.json`, `unicode-sync-timing.json`,
the timestamped UI events, and `unicode-sync.png`.

Four later ordinary single-column reading/bookmark actions were acknowledged by
background sync during a supported redownload. They are not credited to the
earlier button. Final readback contained all nine exact new-account actions,
and the new account had zero pending actions. No host writer, invented server
acknowledgment, private-row edit, or fabricated original-account identity was used.
The original-account backup search was not repeated.

## Errors and bounded retries

The first server-field fill returned `Error (COMMAND_FAILED): Field focus was refused`.
Its advice was `Retry with --debug and inspect diagnostics log for details.`
One fresh-reference retry with `--debug` succeeded. The initial shell batch had
continued to fill the other sign-in fields after this failure; submitting the
empty address produced the normal address-validation message, not a login or OCR
acceptance result. Later batches stopped on command failure.

Tapping the bookmark sheet's exposed Dismiss node did not dismiss it. A later
helper selector reported `Expected exactly one fresh button named Back; found 0. No input dispatched.`
One supported Android Back navigation succeeded. No alternate UI engine was used.

The first redownload request remained Waiting for Wi-Fi because Wi-Fi had not
connected yet. The reader correctly refused the absent local PDF. The planned
Cancel selector reported `Expected exactly one fresh button named Cancel recognition; found 0. No input dispatched.`
The retry restored the route/network, observed actual Downloaded status and exact
original bytes, then disconnected again. One active Read/Cancel retry succeeded.
This failed-precondition attempt is not credited as cancellation acceptance.
It exposed a minor wrong-format message, filed as `t8-oitu`: the PDF's unopened
reader also said `This EPUB is not open. Use the message above to retry.`

Preparatory host reads used a nonexistent artifact-metadata path and two guessed
library paths; the repository artifact record and actual source paths were then
read. The patch command was absent from PATH; its installed absolute path worked.
The initial failed patch left no helper files, so the following capture/hash
redirection failed, while the in-place install still succeeded. The real baseline
was captured afterward and compared to the prior 70-action evidence. One host
audit probe used a nonexistent `collection` key; corrected field access succeeded.
None of these host errors proves a native recognition failure or app crash.

## Cleanup and remaining scope

All three owned downloads were removed through normal UI and confirmation dialogs.
Downloads showed no downloads or retained files. The app was signed out and closed.
The final read-only capture held 79 actions, with the original 28 still pending,
SQLite integrity `ok`, no app process, no book originals or OCR page caches, and
the bundled private English model still present. Media stayed muted in every
capture. Airplane/Wi-Fi/mobile-data returned to `0/1/1`. Large text was unchanged.

The real plugin readback matched all nine new actions before host cleanup. Its
owned controller and Jellyfin process then stopped. Ports 7364/7365 were free,
the owned route was absent, and the owned fixture, passwords, tokens, server logs,
and marker directory were removed. Temporary database copies were auto-removed.
No sole recovery path for a new pending action was deleted: the new account had
zero pending actions and exact acknowledged readback. No earlier backup was removed.
T3 released the binding with `shutdown:false` after cleanup and audit. No further
device action followed release. Nothing remains outstanding from this lane's cleanup.

`t0-ys9g`'s Android cancellation/rendering behavior is accepted on this artifact:
fresh complete inspection remains usable, the original remains accessible, and
retry and active departure work visibly. Native drain and exact late-callback
ordering remain unverified, not silently accepted. Parent owns integration and
any ticket closure. `t0-yy48`'s route-isolation/explicit-button behavior passed.
`t2-00a4` still needs authentic recovery of the original account's 28 pending actions.
`boo-suhu` still needs fresh-install offline OCR on a separate supported target,
native callback-boundary proof, and runtime cross-account ownership coverage.
Physical-phone, two-device, real TalkBack, and legal approval remain separate.
The existing serif-font defect `te-rtok` was not changed. KF8 acceptance was not repeated.

## Repeatable verification

All fixture and audit commands used the pinned project Nix shells. There was no
new host product-test count, broad hardening, coverage, mutation run, PR, or closure.
The current-process read-only log summary had zero null-check error markers and
zero fatal-exception markers; it is not a full-lane crash-history claim. Raw app
logs were not retained. An owned-secret scan found no password or token in evidence.
Trailing whitespace in the read-only memory dump was trimmed; its values were unchanged.

The host-only audit checks the retained snapshots, plugin readback, route/button
ordering, active UI states, cache identity/removal, nonzero stored positions, and
cleanup evidence. It does not drive the device or prove native ordering:

```sh
nix develop --command python3 tool/evidence/reader/integrated/20261103/resumed/audit.py
```
