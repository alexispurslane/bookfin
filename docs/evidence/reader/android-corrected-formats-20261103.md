# Corrected normal Android formats and native replacement

Date: November 3, 2026, America/New_York. This is finite emulator acceptance,
not complete product acceptance. The application source is exactly
`44d53afbe491f28cec0205584ba7f023ec8a10b6`.
The earlier `4ae8c6c` failure remains unchanged baseline evidence in
`android-normal-formats-20261103.md`.

## Result

The missing-format correction works through genuine ordinary Jellyfin Book
responses. The NIST PDF, plain MOBI, PalmDOC MOBI, and Alice KF8 all open through
normal Download and Read controls. The server responses omit both Container
and MediaSources. No response fields or private application state were added.

PDF original-page rendering, extracted-text reflow, both backward boundaries,
conservative fallback, a text-size change, saved character places, and a true
offline process restart have the bounded results below. The modified libmobi
companion installs in place, retains every action, and performs fresh conversion.
Two failures prevent complete acceptance:

- `t2-42og`: KF8 saved resume and bookmark open the chapter's first visible page,
  rather than the recorded nonzero-character passage.
- `t2-00a4`: explicit personal-record sync leaves 28 of the new account's
  37 retained actions pending. The real plugin has nine matching objects.

No production code, app-data reset, uninstall, ticket closure, pull request,
coverage, mutation testing, OCR device action, or child agent was used.

## Exact artifacts

SHA-256 is a hash that identifies exact file bytes. APK is Android's application
package format. Both packages use the same existing disposable debug key.

| Item | Observed identity |
| --- | --- |
| Normal APK | `/Users/alexispurslane/Development/bookfin/.cache/artifacts/bookfin-44d53af-formats.apk` |
| Normal APK bytes | 159,289,190 |
| Normal APK SHA-256 | `f062456644d1c6e8829b289d130e6047e582eb7fd67b139b1b7263be926615e7` |
| Companion APK | `/Users/alexispurslane/Development/bookfin/.cache/artifacts/bookfin-44d53af-replacement/bookfin-replacement.apk` |
| Companion APK bytes | 114,387,933 |
| Companion APK SHA-256 | `e5bdcd3bacfe9f06233c4f845fa56af54e24d19cd0c0cfce9d2479a5506d44f9` |
| Original ARM64 libmobi SHA-256 | `9c641b51da2a96f7d40cc6ce9fc69514ef98eae92074358c838d74310da444bf` |
| Modified ARM64 libmobi SHA-256 | `657b3a35ffa263b42899e48585163e9e5dd32d5c20bf76c4102d3f34516ee56c` |
| Matching source export | `/Users/alexispurslane/Development/bookfin/.cache/artifacts/bookfin-44d53af-source/`; all five manifest hashes verified |
| Device | T3 `local` / `emulator-5554`, ARM64 Android API 36; not a physical phone |
| Fresh binding | `t3-24e09b5660eb05f1e8411513` |
| Ordinary account | Newly generated disposable `research-alice`, not an administrator |
| Server | Owned loopback-only Jellyfin 12.4.0, host port 7364; owned reverse route from emulator port 7365 |
| Plugin | Bookfin Storage 0.1.1.0; exact reviewed ZIP SHA-256 `3b0de5ca1df39baf67c786079898b1ee3b0b09d3bdb86d00ece8a7f5731a9105` |

Both packages were hashed before use. Normal installed readbacks match the
normal APK; companion readbacks match the companion APK. Each record capture
reads the actual installed base APK again. No rebuild or artifact substitution
occurred. The parent's signature, 16 KiB alignment, native-byte comparison,
29-notice, pinned PDFium, and source preparation proof stays under
`tool/evidence/reader/formats/20261103/missing-container/android/`.
Those package checks are not a claim of legal or store approval.

New evidence is under
`tool/evidence/reader/formats/20261103/android-corrected/`.
`artifact-identity.json` records exact source and package identities.
`ordinary-book-dtos.json` contains the server's ordinary Book responses, with
no Container or MediaSources for any of the eight prepared editions.

## Normal reader results

Reflow wraps extracted text to the viewport width. A source character index
counts UTF-16 code units within one original PDF page. It is not a screen
coordinate. PDF reflow sizes use Flutter logical pixels. MOBI text sizes use
CSS pixels. Neither unit denotes physical screen pixels.

| Case | Result | Exact observation and limit |
| --- | --- | --- |
| Original download and format admission | Pass for seven downloaded originals | `corpus.json` and actual private-file readbacks match every original's bytes and SHA-256. NIST, Census, plain MOBI, PalmDOC, KF8, short PDF, and scan PDF use normal controls. Raven is prepared but not downloaded. |
| NIST original PDF | Pass | All 85,781 original bytes match pinned SHA-256 `7b0c1a9fdfc67218b8ba2098f448c100c27070db91736b3c87fed63bfa21d418`. Screenshot 01 shows the full original title page, logo, raster image, and readable fonts. |
| NIST page 5 reflow | Pass | Extracted Introduction/Authority text is visible. The notice says extraction is not checked against the original page; pictures and layout remain in the original. No semantic-order guarantee is inferred. |
| Nonzero PDF character place | Pass, bounded | Normal scrolling records nonzero character indices. The bookmark at page 5, character 592, quotes the Management and Budget passage. Screenshots 02–04 and 14 show that passage rather than only a location event. |
| PDF size change | Pass, bounded | Size changes from 20 to 22. The Office of Management and Budget passage remains visible, with different wrapping. Exact top-line or pixel preservation is not claimed. One Smaller text action later restores 20. |
| PDF leave and reopen | Pass | Back closes the reader. Read reopens original source page 5; selecting reflow restores the saved passage, not the start of the page. Screenshot 04. |
| Long backward boundary | Pass | Contents selects NIST source page 6. Previous page crosses into page 5's final viewport. Screenshot 05 shows the Audience paragraph ending with providers of cloud services. It does not remain at page 6 or jump to page 5's beginning. |
| Short backward boundary | Pass | The committed two-page short PDF reflows. Next reaches River chapter 2; Previous returns River chapter 1 without blank space or a stuck boundary. Screenshot 10 and `short-backward.txt`. |
| Scan fallback | Pass | Committed pixel-only scan reports no extracted text and keeps the original image visible. Screenshot 11. No OCR is attempted. |
| Complex-page fallback | Pass | Intact Census page 1 reports unreliable text order or character mapping and keeps the three-column original visible. Screenshot 12. Raven page 9 is not exercised here. |
| PDF native lifetime | Pass for this finite sequence | NIST original/reflow, close/reopen, then short PDF, scan, Census, full app close, fresh offline process, and NIST original/reflow all work without an observed native abort. No simultaneous-document, stress, exact callback-count, or explicit worker-shutdown proof is inferred. |
| Plain MOBI6 | Pass | Normal Read converts the intact 604-byte source, shows River chapter, the river sentence and local sepia image. Screenshot 06. Back/Read reopens the derived cache. |
| PalmDOC MOBI6 | Pass | Intact 604-byte compressed original converts through normal Read and shows the same intended text/image. Screenshot 07. |
| Alice KF8 admission and text | Pass with known image limitation | Intact 255,506-byte pinned original converts. Contents opens Chapter I; Next shows page 2 text about the daisy-chain and White Rabbit. Screenshots 08–09. |
| KF8 SVG resources | Known gate remains open | The app warns that some images are unsupported; the cover has an unsupported-image description. Existing `t3-9r9u` remains explicit. Opening text is not acceptance of every image. |
| Normal EPUB resources | Preserved prior proof, not repeated | The earlier ordinary EPUB image/font/offline and incremental-sync evidence remains useful. This lane does not relabel the older APK observations as fresh corrected-build EPUB acceptance. |

## True offline restart

The fixture server remains running during this test. The bound device command
turns airplane mode on, Wi-Fi off, and mobile data off. The owned reverse route
is removed. Android reports `Active default network: none`.

The bound close command stops Bookfin. A separate process readback confirms no
Bookfin process before the bound open command starts it again. The cached
library reports that Jellyfin cannot be reached. Normal Read still renders
NIST source page 5. Selecting reflow shows the later Purpose/Audience passage
from the saved nonzero character place. Screenshot 13 pairs visible text with
the offline network evidence.

The retained bookmark remains listed. Selecting it moves back to the earlier
Office of Management and Budget passage. Screenshot 14 shows the destination.
This is visible-text evidence, not an assumption based on a location event.
Airplane mode, Wi-Fi and mobile data are restored afterward.

## In-place replacement and failures

The normal APK creates both plain-MOBI and KF8 bookmarks/resume records before
replacement. The companion installs with `install -r`, using the same key and
existing application data. Every one of the 44 retained action payload hashes
is unchanged immediately afterward: seven previous actions plus 37 actions
from this owned ordinary account.

The companion opens the existing KF8 derived cache, but visible navigation
fails. The saved Chapter I position is
`epubcfi(/6/10!/4/2[pgepubid00003]/4/1:260)`, with the quote beginning
`Alice “without pictures or conversations?”`. Before replacement, screenshot 09
shows page 2 of 21 and the daisy-chain passage. After replacement, Read and the
retained bookmark both show the chapter heading and page 1 of 21. Screenshots
15–16 document that difference. `t2-42og` records the failure. Its cause and
whether normal-process restart alone also triggers it remain unestablished.
Record survival does not mean that visible resume passes.

Fresh modified-library conversion is a separate pass. Normal Remove confirms
removal of the plain MOBI original, derived EPUB, and both manifests. Readback
proves that those files are absent and 2,725 bytes are reclaimed. All personal
record tables remain intact. Normal Download retrieves the same original
again. Read creates a new derived cache and shows the river text and image.
Screenshot 17 is captured after that fresh conversion. The earlier bookmark
remains listed and returns the intended one-page river text. This short source
does not prove nonzero-character MOBI resume.

The installed companion's libmobi bytes match the modified-library hash and
contain `bookfin-interface-compatible-replacement`. Android maps uncompressed
native library entries under the base APK's path. `companion-native-identity.json`
matches the executable mappings to the actual ZIP byte extents for both
libmobi and the converter bridge. Thus this is not a claim based only on an old
derived cache. An initial basename-only mapping filter found no libmobi name;
the ZIP-offset readback resolves that inspection limitation.

This proves a finite runtime replacement path. It does not provide qualified
LGPL compliance review, release signing, store approval, or distribution terms.

During cleanup, explicit Sync now still reports that records remain on this
device. The real plugin has nine immutable objects whose payload hashes match
the local account. The remaining 28 actions are pending and retained. This new
bounded failure is `t2-00a4`. The earlier seven-action sync success is not
discarded, and no private-row insertion or host writer substitutes for Android.
Two preliminary host inventory requests used unsupported query bounds and
returned HTTP 400; the committed `after`/`limit=4` inventory succeeds. Those
host request errors are not the app's sync error diagnosis.

## Cleanup and evidence limits

All 19 screenshots were visually audited. A byte scan finds no generated
password or access token in public evidence. The evidence checker runs through
the Nix development shell and passes. It checks file identities, retained
payloads, native mappings and removal, not coverage or mutation adequacy.

Every device launch, input, setting, screenshot and close uses the fresh bound
command. T3 screenshots also inspect the device. No adb/simctl/ssh UI action or
replacement binding is used. The first server-field fill returns
`Field focus was refused`. Diagnostics are inspected; a fresh snapshot shows
the field focused. The single advised `--debug` retry succeeds. There is no
failed retry or device stop condition. Later fields are focused separately
before filling. No mutation is queued behind another device action.

- All seven owned downloads are removed through normal confirmation dialogs.
  The app reports no downloads and no retained files. Private readback finds
  zero owned download bytes. Cleanup reclaims 748,449 bytes, including original
  files, derived files and manifests.
- The owned account signs out. No user record is deleted. All seven previous
  action payloads survive unchanged, together with the 37 new synthetic actions.
  The 28 pending synthetic actions remain retained, not silently discarded.
- The reader size returns to 20. Airplane mode is off, Wi-Fi is on and mobile
  data is on. Effective media volume remains 0 with the media stream muted.
  No host audio, system font, appearance, or TalkBack setting is changed.
- The app closes through the bound command. Final process readback finds no
  Bookfin process. The owned server exits after its recognized shutdown API.
  Owned ports 7364/7365 are closed and the owned reverse route is removed.
- Owned fixture accounts, media, database copies, credentials and private logs
  are removed after evidence audit. No shared cache or other checkout is erased.
  The companion remains installed, signed out, with retained records.
- `cleanup.json` is the pre-release audit. The final T3 release is performed
  only after evidence and ticket notes are committed, with `shutdown:false`.
  No further device action follows release.

Remaining gates include `t2-42og`, `t2-00a4`, the known KF8 SVG resource gate,
Raven-specific Android fallback, a larger public corpus, authentic older-schema
migration, conflicts/history on two actual Android clients, physical-device
behavior, TalkBack, and qualified signing/distribution/compliance review.
No production OCR source or future OCR APK result is claimed.
The orchestrator owns integration, acceptance decisions and ticket closure.
