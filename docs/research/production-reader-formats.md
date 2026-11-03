# Reader integration candidate

Date: 2026-11-02. Ticket: `boo-mx5i`.

## Scope

This candidate adds production reader code, not Android acceptance or release approval.
The existing EPUB navigator and passive resource importer remain in use.
The reader owns one document and one visible address across formats.
The existing account-scoped record owner stores bookmarks and resume positions.
Existing EPUB anchor serialization remains unchanged.

## PDF

`PdfRuntime` admits native work only from the application isolate.
The dependency-owned worker retains PDFium and its font callbacks.
Documents drain admitted work before disposal. Copied raster bytes, not native images, leave the document owner.
Explicit worker shutdown drains documents and permits a subsequent reopen.
The runtime invariant checker verifies document ownership and initialization state on demand.

The original-page view opens first and supports zoom.
Optional reflow wraps extracted text to the viewport width.
Positions retain a 1-based source page and a UTF-16 character index in that page's source text.
Whitespace normalization retains a source-character map.
Pictures and page layout stay in the original-page view, with an explicit notice in reflow.

Empty text, discontinuous character groups, repeated parallel text groups, highly fragmented text, and invalid character mapping use original-page fallback.
These checks screen geometry and mapping. They do not establish semantic order or correct recognition.
The reflow notice explicitly says that extracted text is not checked against the page.
Search reports pages skipped for unreliable or absent text and caps results at 200 matches.
No OCR or arbitrary table/column reconstruction is implemented.

The pinned NIST page 5 remains a reflow candidate.
Pinned Census page 1 and Raven page 9 retain the explicit unreliable-text fallback.
The public input acquisition script writes a separate ignored cache and verifies the existing manifest's hashes.
Existing research corpus and evidence are unchanged.

## MOBI work already present at the sync-review interruption

The candidate also contains the local libmobi 0.12 importer implemented before the sync correction request.
Its native bridge uses the same bounded reconstruction path as the reviewed proof.
Generated EPUB output passes through the production passive resource importer, including XHTML, CSS, fonts, images, and the existing narrowly supported SVG fallback.
Original MOBI bytes remain unchanged.
Conversion runs away from the UI isolate and serializes through one import queue.

Derived output lives beside the account-owned download in a private reader cache.
Its manifest binds the original digest, conversion policy, and EPUB checksum.
Interrupted or damaged derived output is regenerated without deleting the original.
The reading identity binds the original digest and pinned conversion/import policy, rather than incidental ZIP timestamps.
Generated MOBI6 plain/PalmDOC and pinned Gutenberg KF8 samples pass actual native conversion, resource admission, cache reopen, and damaged-cache recovery tests.
Malformed input fails without publishing a successful cache.

## Remaining gates

- Android original-page/reflow, lifecycle, accessibility, fonts, and offline acceptance remain unverified by this builder.
- EPUB Android gates and the PDF callback-ownership Android gate remain open.
- `t3-ipk1` remains mandatory before release: corresponding source, license notices, installation information, replacement/relink demonstration, and qualified compliance review.
- No new installable format APK is claimed at this checkpoint. The native source/toolchain pins and Android build wiring are present, but Android packaging is not yet checked.
- Bundled local OCR remains `boo-suhu`. Engine selection, model/language scope, measurements, and Android evidence remain open.

The independent sync review takes priority after this safe source milestone.
No format ticket is closed, and no existing acceptance dependency is bypassed.

## Reproduction

Checkpoint verification: 383 Flutter tests pass, with the existing optional real-plugin test skipped.
The three SDK/native-tool checks pass. Analysis reports no issues.
All 27 existing real Chromium engine tests pass after the image dependency alignment to 4.8.0.
`tool/evidence/reader/formats/20261102/` records the final checks and exact installed browser provenance.

Run through the root Nix shell:

```sh
nix develop --command flutter test test/reader --concurrency=1
nix develop --command python3 tool/reader/fetch_pdf_corpus.py
nix develop --command flutter test tool/reader/pdf_corpus_test.dart --concurrency=1
nix develop --command flutter analyze
```

The host native-asset hook warns that iOS SDKs are absent. This candidate does not claim iOS validation.
