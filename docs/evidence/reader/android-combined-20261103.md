# Combined Android acceptance, November 3, 2026

This is bounded acceptance evidence for source `71af2886e722b7366d4d335622e55e18a151a3e0`.
The evidence parent is `ae9f271c357801715ccd09943da041292a20fcf8`.
No production source changed in this lane. No ticket closed.
The evidence directory is `tool/evidence/reader/integrated/20261103/android/`.
The device was host `local`, emulator `emulator-5554`, using one owned T3 binding.
All application launches, input, settings, and screenshots used the returned bound command and T3 screen inspection.
No other device task or child agent ran in this lane.

## Required stop and unfinished device cleanup

Device work stopped after the single recovery attempt failed during ordinary bookmark entry.
The first error was:

```text
Error (COMMAND_FAILED): Field focus was refused
```

Its diagnostic identifier was `mw0zdb3k-c5047495`.
After diagnostics and a fresh complete snapshot, the retry used an ambiguous selector instead of the exact title reference.
The retry returned:

```text
Error (AMBIGUOUS_MATCH): Selector matched 2 distinct actionable elements: role="text-field" value=""
```

Its diagnostic identifier was `mw0zdq1z-bb3b5ba6`.
The retry selector was an operator error, not an established Bookfin defect.
No further device interaction, installation, screenshot, or settings command followed.
A final read-only audit captured retained actions and device state.
No replacement binding, UI fallback, app reset, or private-state injection occurred.

The last observed device state remains incomplete:

| Item | Last observed state |
| --- | --- |
| Bookfin | Signed in, running, unsaved Reading bookmark dialog |
| Owned downloads | Five remain |
| Networking | Airplane mode 1, Wi-Fi 0, mobile data 0 |
| Prior networking | Airplane mode 0, Wi-Fi 1, mobile data 1 |
| Media volume | Muted throughout captured audits |
| System text size | Large, unchanged |
| Owned Alice reading text size | 22 logical pixels, not restored |
| Installed application | Companion APK |

Sign-out, application close, download cleanup, and networking restoration require a separately authorized device lane.
The current lane must not resume those actions after the failed retry.
Ticket `t7-msmk` records the stop and remaining cleanup.

Host cleanup completed before release of the owned binding.
The owned controller and Jellyfin process stopped. Ports 7364 and 7365 are free.
The owned reverse route was removed before the stop and was not recreated.
Generated credentials had mode 600 before removal.
Only owned fixture data, credentials, and private device copies were removed.
All 25 new-account actions were acknowledged, so no pending-action fixture backup was required.
This fixture cannot recover the original account's 28 pending actions.
`cleanup.json` records the host audit. Binding release follows the evidence commit with `shutdown:false`.

## Exact installed artifacts

An APK is an Android application package. SHA-256 identifies its exact bytes.
All artifacts came from the read-only `bookfin-71af288-combined` artifact directory under the main checkout's `.cache/artifacts/`.

| Artifact | SHA-256 |
| --- | --- |
| Normal `bookfin-71af288-arm64-debug.apk` | `129a9a82a338a2e7b5cf1abd154c729866a328295c241063fabd26e38353c270` |
| Companion `replacement/bookfin-replacement.apk` | `d00f1abbcbe58acecbc7627c2ee22b3771c04ad1a73fba9f3214c74f3be26e84` |
| Matching `source/bookfin-source.tar` | `7a73558f74c625f834f70e49bdb2e3ad3686619ad799eaf58842091c90ff4b64` |

The existing, normal, and companion packages passed signing verification before in-place installation.
Their signing certificate SHA-256 is `3d46f8153267daffafa3d91655f9c728d9124b0b32b401dd5f5ad1832411d47d`.
The only changed non-signature entry between normal and companion packages is `lib/arm64-v8a/libmobi.so`.
The parent manifest records model, notices, source, ARM64 library, and 16 KiB alignment checks.
This lane does not repeat or extend distribution approval.

## Ordinary server and retained records

The owned fixture used Jellyfin 12.4.0 and unchanged Bookfin Storage 0.1.1.0.
The plugin SHA-256 is `3b0de5ca1df39baf67c786079898b1ee3b0b09d3bdb86d00ece8a7f5731a9105`.
Ports 7364 and 7365 were checked before fixture startup.
The catalog served actual originals through ordinary Jellyfin book responses.
All six captured book responses omit `Container` and `MediaSources`. No fabricated response supplied format metadata.
`corpus.json`, `long-scan-provenance.json`, and `ordinary-book-dtos.json` record the inputs.

An action is one retained personal-record change. Pending means the device has not acknowledged its upload.
The baseline captured identities and payload hashes for all 44 existing actions before installation.
Every subsequent action snapshot preserves those 44 actions exactly, including source identities and pending flags.
Their original 28 pending actions remain pending.
The normal update preserved all 44 actions.
The companion update preserved all 69 actions exactly across installation: 44 original and 25 new-account actions.
No private account, address, action, or pending flag was rewritten.

## Offline recognition in the normal application

OCR means recognition of text from page images.
The normal application copied its bundled English-fast model and recognized eligible scans while emulator networking was disabled.
The pre-recognition private-file snapshot contains neither the copied model nor an OCR cache.
This was first-use recognition after a data-preserving update, not a fresh application installation.
No cloud service or first-use model download supplied recognition.

| Behavior | Observed result | Evidence |
| --- | --- | --- |
| Recognized reflow | Actual English text appears in reflow | Screenshots 01 and 06 |
| Search | `promise` produces an actual source-page hit | Screenshot 02 |
| Original access | Original image remains accessible | Screenshot 03 |
| Cached reopen | Recognized text remains after leaving and reopening | Screenshots 04 and 08 |
| Offline process restart | Recognized text remains after process absence and restart | Screenshots 05 and 09, process-absence capture |
| Nonzero saved place | Tall scan saves source page 1, character 611 and a bookmark | `long-bookmarked.json`, screenshots 06 and 07 |
| Nonzero restoration | Bookmark return, reopen, and restart show a non-start text region | Screenshots 07, 08, and 09 |
| Historical crop | Actual crop text appears in reflow | Screenshot 10 |

The tall scan draws the unchanged pinned English image six times on one source page.
Its PDF SHA-256 is `545e5843794bc0138fb397412bef477ad33c92935eb5babd1ccfed65ab53c54f`.
The short scan search generated character 145, but that page fits the viewport.
Its bookmark returns to character zero and does not prove nonzero bookmark restoration.
The tall scan provides the nonzero restoration evidence instead.

The item titled Empty scan is the research `scanned.pdf` original.
It recognizes `This page has pixels, not a PDF text layer.`
Therefore it does not establish empty-result fallback.
Recognition was active in a fresh snapshot, but Cancel disappeared before dispatch.
The recovery snapshot showed completed recognition. Active cancellation, native drain, and retry remain unverified.
Failed or empty recognition, saved-address preservation through failure, and account/source/removal lifetime remain unverified.

### Accuracy and resource measurements

Word edits count insertions, deletions, and substitutions against pinned references.
The comparison folds whitespace and preserves punctuation and case.
`ocr-cache-readback.json` retains sanitized native cache output for repeatable scoring.

| Input | Reference words | Word edits | Character edits |
| --- | ---: | ---: | ---: |
| Generated English | 37 | 0 | 0 |
| Six unchanged English image draws | 222 | 0 | 0 |
| Pinned historical crop | 31 | 2 | 4 |

| Quantity | Observation | Measurement limit |
| --- | --- | --- |
| Initial Read command | 17:10:59–17:11:01 UTC, 1.606 seconds | Command settling time, not isolated recognition time |
| First model/cache modification | 17:11:00 UTC | Filesystem timestamps have one-second resolution |
| Reflow request | 17:11:17–17:11:18 UTC, 677 ms | Operator delay separates this request from initial recognition |
| Maximum sampled PSS | 371,821 KiB | 60 samples, about 0.5-second spacing plus command overhead |
| Maximum sampled RSS | 318,124 KiB | Not continuous peak memory |
| Copied English model | 4,113,088 bytes | Logical private-file length |
| First OCR cache | 5,246 bytes | Logical private-file length |
| Four final OCR caches | 41,641 bytes total | Logical private-file lengths |

PSS is resident memory apportioned across processes that share pages.
RSS is resident memory counted without that apportionment. One KiB is 1,024 bytes.
The sampled maxima are not allocator peaks or complete system memory totals.
Private-file measurements exclude databases, the separate cache directory, APK bytes, compiled code, and Android storage accounting.
The copied model SHA-256 is `7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2`.

Cream/sepia surfaces and long-text controls were readable and reachable.
Recognized PDF body text is visibly sans-serif rather than the approved Source Serif 4.
Bug `te-rtok`, under `boo-fs0n`, records this mismatch. No fix was attempted.

## Exact Alice character-address restoration

KF8 is the downloaded Alice ebook format. A CFI is an EPUB character address.
The ordinary Alice original SHA-256 is `d8211269aed55ded8302f289950936db8368b4d4d384c463b722034152f8f1d2`.
At 22 logical pixels, ordinary Contents, Chapter I, then Next produced this saved and bookmarked address:

```text
epubcfi(/6/10!/4/2[pgepubid00003]/4/1:260)
```

Its quote begins with ` Alice “without pictures or conversations?”` and continues into `So she was considering in her own mind`.
No address was injected. Actual rendered text, not only a saved-address event, provides the restoration evidence.

| Behavior | Visible result | Evidence |
| --- | --- | --- |
| Normal cached reopen | Target Alice quote and following passage | Screenshot 14 |
| Bookmark return from page 3 | Target passage | Screenshot 15 |
| Text size 22 to 24 to 22 | Target passage remains visible | Screenshots 13 and 16 |
| Expanded viewport | Target quote and following passage remain visible | Screenshot 17 |
| Offline process restart | Page 2 of 21 and target passage | Screenshot 18b |
| Companion cached reopen | Same saved passage | Screenshot 19 |
| Companion fresh conversion | Same saved passage after ordinary removal and redownload | Screenshot 20 |

Screenshot 17 includes the chapter heading and the target passage. Heading presence alone does not establish restoration failure.
Screenshot 18 is an early loading frame. Screenshot 18b is the rendered restart proof.
Ordinary Alice removal deleted four original/derived files, totaling 460,427 bytes, while preserving actions.
`companion-alice-files-removed.json` proves completed deletion.
`companion-alice-removed.json` captures only the confirmation prompt, not completed deletion.
Ordinary redownload and Read then performed a fresh companion conversion.
Read-only inspection found executable mappings for libmobi and its bridge.
The installed library contains `bookfin-interface-compatible-replacement`.

## Native UTF-8 upload and its limits

UTF-8 encodes Unicode text as bytes for transmission.
Ordinary offline reading and bookmark actions included title `“Café 中文”` and note `Offline English recognition: “déjà vu”, 中文, 🐟.`
After reconnection, background sync uploaded all 25 new-account actions.
Actual unchanged-plugin readback contains 25 matching payload hashes and matching action contents, identities, and causal data.
The new account has zero pending actions. `stop-audit-server.json` and `audit.json` record the comparison.

Explicit Account, Sync now was not reached before the required stop.
Therefore this lane does not establish explicit-retry acceptance.
The earlier original fixture/server was already deleted. No legitimate saved server state recovered that identity in this lane.
New-account success does not prove recovery of the original 28 pending actions.
All original 44 action payloads and identities remain preserved, with those 28 still pending.
Ticket `t2-00a4` remains in progress.

## Evidence audit and remaining gates

The host-only evidence audit runs through the project-managed Nix environment:

```sh
nix develop --command python3 tool/evidence/reader/integrated/20261103/android/audit.py
```

It compares retained actions across captures, installed identities, companion entry differences, real plugin objects, cache hashes, and removal evidence.
It does not drive the device or infer visible behavior from action rows.
The screenshots supply visible-text observations. Capture helpers are read-only except the disposable fixture generator.
Do not rerun capture helpers after the lane's stop.

The following remain separate gates:

- Fresh-install OCR, active cancel/drain/retry, recognition failure, and source/account/download lifetime acceptance.
- Explicit Android Sync now retry and recovery of the original account's 28 pending actions.
- Required device cleanup and restoration after the stopped lane.
- Physical phone, two-device behavior, TalkBack, distribution/legal approval, and orchestrator-owned test hardening.

No acceptance result rests on tap intent alone. No production tests, coverage, mutation testing, publication, or ticket closure occurred in this lane.
