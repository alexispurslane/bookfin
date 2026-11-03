# Normal Android format and single-device sync acceptance

Date: November 3, 2026, America/New_York. This is a bounded acceptance attempt,
not full product acceptance. No production file changed. No production optical
character recognition (OCR), engine selection, coverage campaign, mutation
campaign, pull request, or ticket closure occurred.

## Result

Ordinary Jellyfin downloads of the exact NIST PDF and generated plain MOBI
reach Bookfin intact, but Read rejects both as EPUB archives. New blocker
`t3-jrhf` prevents the PDF renderer and MOBI converter from being exercised
through the normal app. Do not replace this result with standalone reader
proof, invented server metadata, edited app storage, or an older APK.

The generated EPUB still opens normally. Local images, the publisher font,
saved reading places, offline process restart, actual-plugin upload, bookmark
deletion, and download removal have the bounded results below. The format
blocker does not invalidate these separate EPUB and persistence observations.

The evidence directory is
`tool/evidence/reader/formats/20261103/android-normal/`.
Its `artifact-identity.json` identifies the actual installed APK, complete
source export, plugin, emulator, and fresh device binding. SHA-256 is a hash
that identifies exact file bytes.

## Exact application and fixture

| Item | Observed identity or condition |
| --- | --- |
| Application source | `4ae8c6c2299e7ec7c16420663a8fc305e87e6c9a` |
| Normal APK | `/Users/alexispurslane/Development/bookfin/.cache/artifacts/bookfin-4ae8c6c-incremental-sync.apk` |
| Normal APK size | 159,290,067 bytes |
| Normal APK SHA-256 | `610fb123b835858d675302c550e4b6476ddfcd12372aaebac85a7f2f4b51f7ef` |
| Installation | In-place `install -r`; no uninstall, app-data clear, rebuild, or artifact modification |
| Installed readback | Initial, every SQLite capture, and final installed APK hashes match the normal APK |
| Source export | `/Users/alexispurslane/Development/bookfin/.cache/artifacts/bookfin-4ae8c6c-source/`; all five manifest file hashes verified |
| Package verification | 29 exact native notices and pinned PDFium SHA-256 `de19db1c0fb33579bca6ace903af7ccb9d03ad1d3f6c5202970d8d79d7538303` |
| Device | T3 `local` / `emulator-5554`, ARM64 Android API 36; not a physical phone |
| Device binding | Fresh `t3-c1b0700b94e894a1d4e08ade`; no other binding reused |
| Ordinary account | Fresh disposable `research-alice`; not a Jellyfin administrator |
| Server | Owned loopback-only Jellyfin 12.4.0; no live server or publication |
| Plugin | Unchanged Bookfin Storage 0.1.1.0 package, SHA-256 `3b0de5ca1df39baf67c786079898b1ee3b0b09d3bdb86d00ece8a7f5731a9105` |
| Plugin preparation | Existing package tool reproduced exactly the reviewed ZIP hash; installed in this checkout's owned stopped fixture |
| Audio | Media muted throughout observed endpoints; final effective media stream volume 0; no host audio change |

The installed app was inspected before sign-in and was signed out. Existing
native app data was retained. At cleanup, all ten pre-existing entries in the
legacy shared-preference file remained byte-equivalent by parsed XML entry;
no existing entry changed and no new entry appeared in that file. This is a
narrow preservation check, not proof that every native app file is unchanged.

`corpus.json` identifies nine prepared editions and their exact file hashes.
Only NIST, plain MOBI, and the generated image/font EPUB were downloaded in
this attempt. Census, Raven, the other MOBI originals, and generated PDF
boundary fixtures were prepared but not opened. Preparing a fixture is not a
runtime pass. The pinned public PDFs are full originals, not page derivatives.

## Format acceptance

Reader font sizes below use CSS pixels, the embedded web reader's layout
unit, not physical screen pixels. The original image dimensions use source
image pixels.

| Case | Result | Evidence and limit |
| --- | --- | --- |
| Real ordinary-user library and original download | Pass for NIST, plain MOBI, and generated EPUB | Jellyfin scans real files; normal app selects `Normal formats`; HTTP observer records unmodified 200 download responses. Private completed files match the fixture hashes. |
| NIST original PDF Read | Failed | Screenshot 01 and `nist-rejection.txt`: `Unsupported EPUB ZIP directory.` Original download is 85,781 bytes; private digest matches pinned `7b0c1a9fdfc67218b8ba2098f448c100c27070db91736b3c87fed63bfa21d418`. |
| Generated plain MOBI Read | Failed | Screenshot 02 and `mobi-rejection.txt`: same EPUB error. Completed original is 604 bytes and matches `corpus.json`. No successful converted cache is published. |
| PDF original-page view and reflow | Blocked, not exercised | NIST never reaches the PDF document owner. No PDF page image, reflow text, or PDF character-address pass is claimed. |
| Census complex-text and Raven poor-text fallback | Not attempted | Exact originals were prepared. The earlier host fallback decisions are not Android acceptance. |
| Long/short PDF Next and Previous boundaries | Not attempted | The normal PDF entry prerequisite fails. No pagination-correction pass is inferred from source tests. |
| PDF nonzero source-character resume/bookmark and offline restart | Not attempted | No PDF position or bookmark could be created in the normal app. |
| Repeated PDF mode taps, images, native callback/disposal/reopen | Not attempted | The PDF native runtime was not entered. An empty native error log cannot prove callbacks or disposal. |
| PalmDOC and KF8 conversion/cache reopen | Not attempted | Supported originals were prepared, but plain-MOBI admission already fails. No standalone native harness substitutes for normal-app conversion. |
| EPUB PNG and JPEG | Pass for the generated fixture | Screenshot 03; native document readback reports both decoded images at 24 × 24 source pixels. Each is displayed as the fixture's enlarged sepia square. |
| EPUB publisher font | Pass for sampled text | `epub-initial-document.json` records the loaded font and actual Source Serif 4 custom-font glyph use for sampled heading/paragraph nodes. A declared CSS font alone is not the evidence. |
| EPUB larger text | Bounded pass | Size 20 to 22 keeps the bookmarked passage 5 visible and preserves its saved address. Screenshot 04 shows that the first visible line moves to an earlier paragraph tail. This is not exact top-line retention. |
| EPUB leave/reopen | Pass at size 22 | `epub-offline-reopen-ready.txt`: harbour passages 7–10 and page 4 of 6 return without a connection. |
| EPUB offline process restart | Pass for saved text, address, font size, and bookmarks | Android process changes from 30739 to 3591. Screenshot 05, native visible-document readback, and exact copied SQLite payloads agree. |
| Download removal and reporting | Pass for original files only | EPUB reports 135,959 bytes before removal. Its completed original and 266-byte manifest disappear. All seven retained actions and every normalized table remain unchanged. Total owned original bytes go from 222,344 to 86,385, then 0 after remaining downloads are removed. |
| MOBI original plus derived-cache reclamation | Not proved | No converter cache exists because format entry failed. Removing the 604-byte original does not establish derived-cache accounting. |

### Ordinary Book response and reader selection

`ordinary-book-dtos.json` records the real ordinary-user responses. Jellyfin
omits both `Container` and `MediaSources` for all nine Book items, including
the PDF and MOBI originals. No response fields were fabricated for acceptance.

The exact catalog assignment in `lib/catalog/model.dart` is:

```dart
        container:
            source['Container'] as String? ??
            item['Container'] as String? ??
            '',
```

where

- `container` = the source format string stored on the downloaded edition.
- `source` = the current media-source map, which has no Container value for these Book responses.
- `item` = the outer Jellyfin Book response, which also has no Container value.
- `String?` = a string that can be absent; `??` selects the next value when the preceding value is absent.
- `''` = the empty string used when neither response supplies the format.

The exact subsequent branch in `lib/reader/platform_io.dart` is:

```dart
  if (source.container.toLowerCase() == 'mobi' ||
      source.container.toLowerCase() == 'azw3') {
    return importMobi(await _verifiedFile(uri));
  }
  if (source.container.toLowerCase() != 'pdf') {
    return EpubDocument(await loadPublication(uri));
  }
```

where

- `source` = the edition's `SourceFile`, which carries the empty `container` string in both failing observations.
- `container` = the same source format string defined above.
- `toLowerCase()` = the string operation that changes format letters to lowercase.
- `uri` = the verified local completed-download file address.
- `loadPublication()` = the production EPUB admission function that checks the local EPUB archive.
- `EpubDocument` = the document wrapper for an admitted EPUB publication.
- `_verifiedFile()` = the always-on guard that admits only the expected bounded local download file.
- `importMobi()` = the production native MOBI conversion and derived-EPUB admission function.

The preceding MOBI/AZW3 branch also does not match an empty format string.
The new blocker owns the correction. This acceptance lane does not select a
format-detection redesign or edit production code.

## Actual-plugin and normalized Android persistence

SQLite is the local database used by the normal Android app. A retained action
is one immutable record change. A pending action is a retained action whose
upload has not been acknowledged. A deletion action keeps its earlier action
but stores a deleted current value. The discovery cursor records how far the
app has admitted the server's ordered changes.

`readback.py` copies only the existing database files, opens the private copies
on the host, checks database integrity, and exports only the owned ordinary
account. It does not write the Android database. Each export includes a fresh
installed-APK hash. A host copy is evidence of stored Android records, not a
second Android client and not an Android timing measurement.

| Observation | Retained actions | Pending actions | Meaning |
| --- | --- | --- | --- |
| First EPUB bookmark | 4 | 4 | Initial reading position, later positions, and the first bookmark are durable. |
| Offline second bookmark, before restart | 6 | 6 | A new reading position and a second bookmark are created by the real app while disconnected. |
| Offline restart and failed sync | 6 | 6 | Exact original action payload hashes survive restart and the refused connection. |
| Direct actual-plugin sync | 6 | 0 | All six immutable actions reach the real plugin; only acknowledgment/discovery state changes locally. |
| First bookmark deleted | 7 | 1 | App UI removes the first visible bookmark while the second remains. The six earlier payload hashes remain unchanged. |
| Restart after deletion | 7 | 0 | Startup synchronization uploads the deletion. The first bookmark stays absent and the second remains visible. |
| All owned downloads removed | 7 | 0 | Every normalized account/action/version/coverage row remains identical to the pre-removal snapshot. |

`first-sync-server.json` and `deletion-synced-server.json` use the existing
actual plugin API with the ordinary accounts. Server payload hashes match the
Android retained-action hashes exactly. Bob's independent ordinary account
sees no objects. This is bounded read isolation, not a new forged-owner or
complete authentication suite. The plugin retains seven immutable objects,
including the deletion action; a bookmark deletion is not server journal
compaction.

The initial catalog/download observer forwards only GET and POST. A sync
upload uses PUT, so the first online upload attempt through that observer
failed without losing pending actions. The owned reverse route was changed
from emulator port 7365 → host observer 7365 to emulator port 7365 → real
Jellyfin 7364. The app address, account identity, plugin package, and protocol
did not change. Direct Sync now then reported `Personal records are synced.`
The observer failure is a fixture limitation, not a Bookfin/plugin defect.

Offline evidence does not mean merely stopping the server. During the offline
restart, airplane mode was on, Wi-Fi and mobile data were off, Android reported
`Active default network: none`, and the owned fixture reverse route was
removed. The host server remained running. This prevents loopback forwarding
from silently bypassing the offline condition.

The restarted reading position stores resource `OEBPS/Text/one.xhtml` and
`epubcfi(/6/2!/4/30/1:0)`. An EPUB canonical fragment identifier (CFI) is a
locator into the EPUB's text structure. The saved quote starts `Harbour
passage 7. The reader followed the shoreline`, matching the visible text in
screenshot 05 and the native document readback. This EPUB locator is not the
unproved PDF source-character position.

These are a few real retained actions, not a storage-growth benchmark. Snapshot
equality does not measure which physical SQLite pages or flash bytes a save
rewrites. No Android save-latency, memory-growth, battery, or power-loss claim
follows from the host measurement report or these readbacks.

## Native replacement and remaining acceptance gates

The supplied same-key companion remains unchanged and uninstalled:
`/Users/alexispurslane/Development/bookfin/.cache/artifacts/bookfin-4ae8c6c-replacement/bookfin-replacement.apk`,
SHA-256 `3a1dd3864a5aa4361750b71430c626f4a3531e8eb056047ad7db7f86688f7849`.
The matching source export and its installation instructions were verified,
but the required ordinary MOBI bookmark/resume cannot be created on the normal
APK. Installing a companion while its converter is unreachable would not prove
that the modified converter loaded. No pre-existing converted cache, EPUB
bookmark, fake MOBI state, uninstall, or reset substitutes for that gate.

| Remaining gate | Exact missing proof |
| --- | --- |
| `boo-mx5i` | Correct ordinary PDF/MOBI admission, then the named original/reflow/fallback/boundary/position/cache/reclamation cases on the exact corrected normal APK. |
| `t0-ebxa` | Actual normal Android PDF text, raster/font callbacks, disposal, and reopen after successful ordinary PDF admission. |
| `t3-ipk1` | Ordinary MOBI reading and records before in-place companion installation, preserved records afterward, and fresh modified-library conversion; qualified compliance and signing/distribution review remain separate. |
| `boo-3oq0` | Two actual Android clients, concurrent offline conflicts, preserved conflict positions, listening history, retry/clock cases, and their UI acceptance. No second Android device was used here. |
| `t6-t9po` migration | A real compatible older app/schema artifact and authentic same-account old-schema state, followed by an in-place normal upgrade. This attempt's fresh account starts normalized. Directly inserting new-schema rows would not test migration. |
| `t6-t9po` scale/performance | Android measurements with a representative retained history; these seven actions and host timings are not that measurement. |
| TalkBack | Known host automation/service coexistence gate `t2-u76g`; no TalkBack attempt or app defect inferred here. |
| Physical device and compliance | No physical phone, release signing, distribution approval, or qualified legal/compliance acceptance. |
| Production OCR | Not implemented or selected by this attempt; prior research OCR evidence stays separate. |

## Device-command recovery and cleanup

Every launch, relaunch, tap, text entry, network setting, screenshot, and close
used the fresh device-bound command returned by T3. `device_screenshot` also
inspected the device. No adb/simctl/ssh UI action, queued mutation, replacement
binding, host-audio change, or child agent was used. SDK adb was limited to
installation, package/log/file readback, and owned port forwards.

Two separate device-command failures each recovered on their single advised
retry. There was no repeated failed retry or device stop condition:

- A non-issued suffixed Back reference returned `Ref @e2 was not issued by the current ref frame`. A fresh interactive snapshot supplied `@e2`; that retry succeeded.
- A later search-field fill returned `Field focus was refused`. Its diagnostics were inspected, a fresh snapshot showed the field focused, and the one retry with `--debug` succeeded.

The diagnostic files remain in the evidence directory. A failed preliminary
host readback used the wrong API field name, and an initial shell `find -exec`
read failed quoting; neither is reader or device acceptance. The corrected
read-only evidence tools produced the retained JSON checks.

Cleanup has these observed results:

- All three owned downloads and manifests are removed through normal confirmation dialogs; the app reports no downloads and no retained files.
- The ordinary account signs out through the app. The signed-out screen is screenshot 11. No user account or unsynced user record was deleted.
- The owned account's seven acknowledged synthetic journal actions remain in private app SQLite by design. The normal app has no account-journal purge UI. No direct SQLite deletion or app-data reset was used to erase that retained history.
- Reader size returns to 20. No global theme, system font, TalkBack, or host audio setting was changed. Airplane off, Wi-Fi on, and mobile data on match the baseline; media remains muted with effective volume 0.
- Bound `close dev.bookfin.bookfin` succeeds. Subsequent SDK readback finds no Bookfin process and an empty native error log. This is not proof of a PDF callback path that never ran.
- The recognized server shuts down through its own fixture command. Only the owned observer PID is terminated. Both processes and loopback ports 7364/7365 are absent afterward.
- Owned reverse and WebView diagnostic forwards are removed. The unrelated pre-existing scrcpy forward on port 51800 remains untouched. No owned build daemon remains.
- T3 releases the Device panel with `shutdown:false`, after process verification. The emulator is not shut down.

All eleven screenshots were visually audited together and contain only the
synthetic library, public document names, ordinary fixture identity, and app
controls. No password or token appears in them. Public evidence is also
checked against the private generated credentials before the owned host
fixture, account files, database copies, and logs are removed.

`evidence-checks.json` records successful artifact, payload, restart, server,
and download-removal comparisons. These are evidence consistency checks, not
coverage or mutation testing. The orchestrator owns integration and ticket
closure. `t3-jrhf` must be corrected before the normal format milestone can
pass.
