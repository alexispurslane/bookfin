# Bundled English recognition

## Scope and acceptance

OCR means optical character recognition: turning page images into text.
The user selected fully bundled English-fast recognition on November 3, 2026.
English is the only supported recognition language. Other languages are unsupported.
Bookfin does not download models or send pages to a recognition service.

This implementation is a reviewable production-source milestone for `boo-suhu`.
It is not Android acceptance or permission to distribute the application.
The separate normal-reader acceptance run on `4ae8c6c` does not accept OCR.
No device installation, UI action, simulator action, or acceptance server belongs
to this implementation work.

## One reader and one source owner

The existing PDF document supplies page text, original-page images and source-page
addresses. Recognition supplies `PdfText` through that same document. It does not
create another reader, source identity, search index, bookmark store or position
store. EPUB and MOBI behavior do not use recognition.

An image-only page starts English recognition when its text is requested.
An unreliable existing text layer keeps its conservative original-page fallback.
The reader offers “Try English recognition” for that page. This does not claim
that the source text layer itself is defective. Ordinary usable text does not
start recognition.

The existing reflow and search operations consume recognized page text. Character
offsets refer to that page's recognized text. Addresses, resume records and
bookmarks still belong to the owning edition, source digest and source page.
Original pages remain available while recognition runs and after failure.
Neither extracted text nor recognized text is a checked transcription.
The existing conservative fragmentation and parallel-row counts also screen
recognized lines. This is not a general table, column or reading-order repair.

The document owns the selected page text for every reader operation. Search and
the viewport do not choose different text layers. An unreliable extracted layer
stays selected until the user requests recognition or verified recognition already
exists for that source page. The explicit request remains in effect for the open
document. Successful recognition stays selected for later requests and reopening.
The document keeps at most sixteen successful recognized pages in memory.
This also preserves the chosen text when saving its cache fails. Each reuse still
enters the existing download ownership interval and verifies the original bytes.

## Text coordinates and compatibility

A text representation identifies the exact text that gives character numbers meaning.
Each new PDF text address includes its text representation. It covers the PDF text
policy, PDFium version, extraction or exact recognition version, and SHA-256 of
the complete source-page text. Recognition version 2 includes the corrected decoder
and the exact engine and English model versions. The decoder accepts the pinned
`ocr_line`, `ocr_header`, `ocr_textfloat` and `ocr_caption` classes through one
geometry check. It rejects nested textual lines and nested recognized words.

A character number is a zero-based UTF-16 code-unit offset within that source-page
text. It is not a position within the PDF file or the displayed reflow layout.
The document creates addresses for search and scrolling. The document also resolves
saved addresses against the current text representation before the viewport applies
a nonzero character number. A changed model, decoder, policy or source-page text
cannot silently reuse another text representation's character numbers.

Source compatibility and text compatibility are separate. An unchanged verified
original keeps its source-page address through text-policy and engine changes.
The existing edition and account checks still belong to `ReaderSession`.
Different original bytes still reject the saved address.

An unresolved address retains its original character number, quote and text
representation. The viewport displays the original source page. Failed recognition,
missing or damaged cache, and cancellation do not replace that address with zero.
The existing resume and bookmark owners persist the unresolved address unchanged.
Choosing a source page in Contents explicitly starts that page at character zero.
Compatible text still restores and updates nonzero reflow positions normally.

Legacy PDF addresses have no text representation. Character zero remains a valid
source-page start. A nonzero legacy character is ambiguous between extracted and
recognized text. Bookfin retains that address but displays its original source page
instead of interpreting that character in current text. No second bookmark or resume
store is introduced.

## Existing download ownership

`LocalDownloads.readLocalFile` remains the storage owner. Its optional ownership
callback exposes whether an admitted read still belongs to the selected account
and source. Removal revokes the active read before queued deletion. Account or
catalog changes revoke it through the existing download generation. Removal and
account restoration still wait for the admitted read to drain before reclaiming
its files. Existing conversion callers retain that ordering.

Recognition reads and publishes only inside that existing ownership interval.
`ReaderSession` also invalidates recognition when its document leaves the session.
No late result can publish after either owner revokes it. Cache publication checks
ownership immediately before its synchronous atomic rename. Native work is not
forcibly interrupted. Cancellation discards its result and lets the current page
finish safely.
Retry during a canceled page drain waits behind that page. It does not reuse the
canceled result or start a second native operation.

## Cache and bounds

Recognized text is derived storage: files regenerated from a saved original.
Each account/source directory contains its own `.bookfin-ocr` subtree. The shared
derived-storage helper counts and removes both OCR and MOBI files. It never follows
cache-directory links or counts/removes targets reached through symbolic links.

The cache key covers the verified original SHA-256, source-page number, text policy,
wrapper version, engine version, Leptonica version and exact model hash. Cached
hOCR, an HTML description of recognized words and page geometry, also has a content
hash. Cache reads verify the original bytes again and reject damaged records.
Failed or canceled recognition is not cached. After reopening, recognition can retry
after corruption. Storage failure leaves readable text for that visit and reports
that the cache could not be saved.

The coordinator admits at most one active page and one waiting page. Waiting pages
do not hold rendered images. The native worker admits one page, rejects competing
pages, and closes only after that page drains. A process-wide ownership guard
prevents a second native engine from starting. The native worker belongs to the
Flutter engine, not an Android activity. Activity replacement does not destroy a
live recognition operation. Flutter-engine detachment removes channel callbacks
and drains the worker.

The PDF raster limit remains 1,600 pixels wide and 4,000 pixels high, at most
6.4 million pixels. Recognition adds a grayscale copy. This bound is not a peak
memory guarantee. Recognition output is bounded. The PDF document waits for text
work, native recognition close and native PDF disposal, in that order. The shared
PDFium owner stops its worker only after all documents close. No extra PDFium
initialization or font-callback owner is introduced.
If recognition close reports an error, PDF disposal still runs. The reader keeps
its existing release-failure gate and requires restart before another document.

Fatal native errors settle the admitted operation with the original Java `Error`.
The worker then closes itself and rejects later operations. Its close future also
reports the failure, so document disposal does not wait forever or hide the failure.
Cleanup errors remain attached to the original failure. A fatal cleanup error takes
precedence over an ordinary operation exception. An unsafe cleanup also closes the
worker. The Android channel and reader require restart rather than offer recognition
retry. Ordinary `IOException` failures can retry after successful engine cleanup.
The process-wide engine permit is released on initialization, operation and close
failure paths. Native invariant failures remain errors, not successful fallbacks.

The coordinator's invariants are bounded page admission, at most sixteen selected
readable pages, and no live recognition status after close.
`BundledEnglishText.checkInvariants()` checks them on demand.
The PDF and download owners retain their existing invariant checkers.

## Pinned inputs

Research source `838d8a4` and investigation commits `fe77f9e` and `562dec2` supplied
the selected pins. The preserved research checkout and its artifacts are read-only
inputs. None of its obsolete production branch was imported.

| Input | Version or bytes | SHA-256 |
| --- | --- | --- |
| Tesseract4Android AAR | 4.9.0 | bce5d6413a1a5ae3d7240033fbbc851ba3217d0a08d9769400e17a077f42cb2a |
| Wrapper and native source archive | 4.9.0, Tesseract 5.5.1, Leptonica 1.85.0 | 4569f9093d641d13188ba2dd36a74396661eaa3f9e44637ff1cac9a36076a20e |
| English-fast model | tessdata_fast 4.1.0, 4,113,088 bytes | 7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2 |
| Model license | Apache-2.0 | cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30 |

`nix/ocr.nix` pins all four inputs. Gradle verifies the exact local AAR and bundled
model before building. Android also verifies the private installed model before
initialization. Only `eng.traineddata` is prepared or packaged. English-best,
Latin-fast, ML Kit and runtime language downloads are absent.

## Verification boundaries

Production-coordinator tests hold only the platform recognition response. They use
real PDFium pages, actual account/source ownership and actual cache files. They
check cache reuse, changed source bytes, corruption, explicit retry, failed
recognition, leaving/reopening, removal, account changes and source changes.
Widget tests exercise the existing viewport's reflow, search, source-page links,
English-only wording, cancellation and original-page display. Their image/native
response boundaries are controlled fixtures, not Android recognition.

Review-correction tests also use the actual SQLite record owner. They close and
reopen the database and create a new reader session around the same original.
They retain page-two nonzero recognized resume and bookmark addresses after missing
or damaged cache, empty recognition, recognition exceptions and active cancellation.
They test changed text, model and policy, ambiguous legacy addresses, and compatible
nonzero reflow restoration. These are host tests, not Android process-restart tests.

The host-native test sends an actual PDFium rendering of the pinned generated
English scan to the Nix Tesseract executable. It uses the exact selected English
model and then the production coordinator, cache, resume and bookmark stores.
The host engine is Tesseract 5.5.3 with Leptonica 1.87.0, not the Android engine.
The complete generated-English reference matches after whitespace normalization.
This proves that boundary, not historical scan accuracy or Android behavior.
The fixture stays under the project cache because this host's Leptonica input
lookup failed for Nix-shell temporary paths. No source document is changed.

The Java test runs the production native-worker coordinator with a held engine
boundary. It proves bounded admission, no parallel engine initialization, close
ordering, rejection after close, and recovery from initialization failure. It
does not run Android JNI or its selected native libraries.

Prior Android measurements remain research-only in
`tool/evidence/reader/ocr/20261102/android-device` and
`tool/evidence/reader/ocr/20261103/android-renewed` in the research history.
Those reports are not production OCR acceptance. Full historical pages remain
unscored without independent transcriptions. No accuracy threshold is invented.

## Notices, sources and distribution limits

The wrapper, Tesseract and English model carry Apache-2.0 licenses. Preserve those
licenses and applicable notices. Mark changes when distributing modified sources.
The pinned archive contains the original native sources and their notices.
Leptonica requires its copyright, conditions and disclaimer with binary
distributions. PNG Reference Library License version 2 preserves attribution and
its notice, disallows false origin claims and requires altered sources to be marked.
The IJG README requires its original source notice when sources are distributed
and its acknowledgement with executables. Bookfin includes this acknowledgement:
“This software is based in part on the work of the Independent JPEG Group.”

Exact source notices, the model license, and Bookfin's acknowledgement appear in
`assets/licenses/ocr` and the existing application license registry. Their manifest
records exact hashes. No separate upstream NOTICE file was found in the pinned
archive. The source archive includes unmodified upstream source, not a claim that
Bookfin rebuilt the published AAR byte for byte.

The source handoff includes the exact committed Bookfin archive, pinned complete
Tesseract4Android/native source archive, exact English model and model license,
plus the existing libmobi source and LGPL/GPL texts. Existing PDFium and libmobi
distribution, replacement and installation-information gates remain open. The
English selection does not approve legal terms, source delivery, signing/store
restrictions, reverse-engineering restrictions, or release distribution. Obtain
the parent's distribution decision and qualified compliance review before release.
No production source offer, store eligibility or compliance clearance is claimed.

## Reproduction and handoff

Run commands through the project Nix shell. No global toolchain or shell-profile
change is needed. Work on one heavy command at a time.

```sh
nix develop --command python3 tool/reader/ocr_package.py prepare --notices
nix develop --command bash tool/bookfin test
nix develop --command bash tool/bookfin analyze
```

Commit all source, tests, notices, ticket updates and test evidence before the
production candidate build. Export matching source from that clean commit:

```sh
nix develop --command python3 tool/reader/native_package.py sources .cache/artifacts/ocr-source
nix develop --command bash tool/bookfin build-android
```

The APK includes the source commit and its exact Git-archive hash. The verifier
rejects a dirty source stamp. It checks the exact model, all selected AAR native
bytes, every OCR notice, ARM64-only native contents, 16 KiB ELF load alignment,
16 KiB package alignment, the APK signature, and the allowed application
permissions. Existing Internet access serves Jellyfin. It is not added for OCR.
Gradle filters dependency native libraries to the requested Flutter Android
targets. The normal ARM64 handoff does not carry unusable 32-bit or x86 libraries.
The evidence manifest binds the APK hash to the source export and build logs.
This is recorded build provenance, not a claim of reproducible debug signing.

The parent still needs normal-app Android OCR acceptance after a fresh offline
install, reflow/search and source-page navigation, cached reopening, active
cancellation, source/account/removal changes, failure/retry, peak memory and
latency measurements, and inspection of the approved immersive reader layout.
Coverage and mutation campaigns wait for user acceptance.
