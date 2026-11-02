# Reader format feasibility

Research date: November 1, 2026. Ticket: `boo-73yj`. Base: `a6bfc1cc82b1ce8dc1705fee5408d868a9dfb6a1`.

## Result and scope

Local MOBI conversion and true PDF text reflow work on the generated samples in this checkout.
The Android native libraries also compile and link for ARM64, the 64-bit ARM architecture.
These results do not establish released format support.
No user-supplied books are available, and none passed these tests.
No emulator, phone, shared app installation, or production reader UI was used.

The experiments live in `tool/research/readers/`.
They do not change the shared Flutter app, shared dependencies, shared SDK, or shared Nix flake.
The research flake pins the same nixpkgs revision as the project.
It adds a small libmobi derivation, hash-pinned PDFium inputs, and a versioned KF8 fixture.

Reflow means extracting text and laying it out again at a new width.
Original-page rendering preserves the PDF page and scales its picture.
The proofs exercise both paths separately.
They do not treat page zoom as reflow.
They do not relate audio positions to text positions.

| Term | Meaning in this report |
| --- | --- |
| File hash or SHA-256 | A content fingerprint calculated from the exact file bytes |
| EPUB spine | The ordered list of chapter files for reading |
| Locator | A saved reading position inside one edition |
| Native library | Compiled machine code that Dart calls through a boundary |
| SDK | Android's platform files and build tools |
| NDK | Android's native C and C++ compiler tools |
| API level | Android's numbered platform interface version |
| APK | An Android application installation package |
| PDF point | One seventy-second of an inch in the PDF coordinate system |
| Pixel | One cell in the rendered output image, distinct from a PDF point |
| Tagged PDF | A PDF with an explicit logical content structure |
| DRM | Access restrictions, including encrypted ebook content |

## Observed format matrix

“Observed” means that a host-side fixture check passed, not that an Android reader passed user testing.
The generated samples have a CC0 dedication.
The external KF8 sample is public domain in the United States and retains Project Gutenberg's terms.
See `tool/research/readers/fixtures/README.md` for sources and rights.

| Input | Real operation and result | Source position available | Limits not proved |
| --- | --- | --- | --- |
| Generated EPUB3 | Dart epubx 4.0.0 parses chapter text and embedded PNG bytes | Spine resource and chapter ID exist in the source | No EPUB navigator, font controls, search, font embedding, complex styles, fixed layout, or large-book rendering test |
| Local HTML | Real HTML parsing and allowlist filtering preserve a heading, local PNG reference, and internal link | Element ID and source document can identify a location | Host filter only. No Android WebView request interception or browser security test |
| Markdown | Dart markdown 7.3.0 renders headings, lists, code, and a local image reference | Source text or normalized document can identify a location | Embedded HTML remains active markup until separately filtered. The renderer alone is not a sanitizer |
| Generated MOBI6, compression type 1 | libmobi 0.12 converts unencrypted content and an image into EPUB. Dart parses both | Converted resource plus text location, tied to source hash and converter version | Minimal English sample, not every legacy code page or dictionary |
| Generated MOBI6, compression type 2 | Same successful conversion and Dart readback | Same as compression type 1 | Generated compressed payload uses literal bytes. It does not exercise every PalmDOC compression instruction |
| Project Gutenberg MOBI8/KF8 | A real 255,506-byte, PalmDOC-compressed Alice edition converts to a 29-entry EPUB. Dart reads text and images | Converted chapter resources exist | This is standalone KF8, not a hybrid KF7/KF8 file, KFX, DRM, or a user book |
| Simple two-page PDF | PDFium extracts text and character rectangles. The proof lays extracted text out again at 360- and 720-point widths | Source hash, zero-based source page, PDFium character index, and character rectangle | ASCII fixture. Untested tag trees, ligatures, non-BMP Unicode, bidirectional text, and font-map failures |
| Two-column PDF | A geometry-based proof reads the entire left column before the right column | Original character indices survive the reordered display | A deliberately simple two-column geometry. Not a general document-layout solver |
| PDF headings | Larger text produces the two expected heading candidates | Candidate retains source page and character rectangles | Font size is a heuristic, not a semantic heading guarantee |
| PDF table | Extraction succeeds but the column heuristic groups labels before amounts | Source rectangles remain available | Row relationships are wrong. Treat this as a known reflow failure, not a supported table result |
| Raster-only PDF | Dart/PDFium renders the original page at 360 pixels wide. Text extraction returns no text | Original page remains the valid reading location | No OCR, search, or text reflow exists for this sample |
| PDF pictures in reflow | Original-page rendering preserves the image in the simple PDF | The original source page remains accessible | The text-only reflow proof omits pictures. Interleaved image extraction is not proved |

The four Dart EPUB checks exercise the generated EPUB and all three MOBI conversions.
The three Dart PDF/Markdown checks use the actual package APIs and PDFium binary.
The Python behavior suite has nine tests.
Seven tests first failed through missing behavior, not missing imports or syntax.
Two negative checks passed against the initial empty proof and do not count as red tests.
The final run must report the exact test counts separately from extraction observations.
The recorded final run passes all 16 checks: nine Python, three Dart PDF/Markdown, and four Dart EPUB/conversion tests.
The snapshots live in `tool/research/readers/evidence/`.

## Engines and packaging candidates

An ABI is the native calling and binary convention.
FFI lets Dart call native C functions.
A platform view embeds an Android view inside Flutter.
A method channel exchanges commands between Dart and Android code.

| Candidate and inspected version | License and distribution work | Android and Flutter path | Evidence and recommendation |
| --- | --- | --- | --- |
| pdfrx 2.11.0, pdfrx_engine 0.9.0, pdfium_dart/pdfium_flutter 0.4.1 | MIT wrappers. Include their notices and PDFium's third-party notices | Existing Flutter viewer and Dart FFI. Current wrappers require Flutter 3.47 / Dart 3.13 | Host Dart extraction and original-page rendering pass. Prefer this path for original PDF pages and extraction. It does not supply complete text reflow |
| PDFium chromium/8125, version 158.0.8125.0 | PDFium BSD-style terms plus component-specific notices. The binary archive contains `licenses/` | Android ARM64 shared library. The inspected build targets minimum API 23 and excludes V8 and XFA | Host binary executes. Android binary links. Use hash-pinned, non-V8 artifacts. Do not ship only the wrapper's MIT notice |
| libmobi 0.12 | LGPL-3.0-or-later, plus bundled component notices | A C shared library called through Dart FFI. No Python, server, or desktop conversion process is required in the app | Three conversions pass. Android ARM64 compilation and linkage pass. Last release is June 17, 2024. The inspected default-branch commit is October 29, 2024. This is a maintenance risk, not evidence of active upkeep |
| Readium Kotlin Toolkit 3.4.0 | BSD-3-Clause core. Optional adapters and DRM components have separate terms | Native EPUB navigator through a platform view and method channel. Its documented minimum Android API is 24 and compile SDK is 37 | Source inspection only. Release dated September 11, 2026. Candidate for a maintained EPUB navigator, not yet a selected or built Flutter integration. The project currently has compile SDK 36 |
| epubx 4.0.0 | MIT | Pure Dart EPUB parser, not a reader or layout engine | Actual parsing passes. Published June 30, 2023. Its archive/image version ranges conflict with pdfrx_engine 0.9.0. Keep it out of production selection without a replacement or reviewed update |
| Dart markdown 7.3.0 | BSD-style, three clauses | Pure Dart Markdown-to-HTML conversion | Real sample renders. Feed its output into the same passive-content boundary as HTML and EPUB. Do not trust its embedded HTML |
| MuPDF 1.27.2 in the pinned nixpkgs | AGPL-3.0-or-later or a separately purchased commercial license. Commercial terms are not established here | Native Android engine with structured-text APIs and reflow tools. A Flutter bridge is still necessary | Source and license alternative only. No MuPDF binary, conversion, reflow, Android build, or size measurement ran. Do not claim it solves arbitrary columns or scans |
| calibre 9.15.0 in the pinned nixpkgs | GPL-3.0-or-later for the relevant conversion code. Bundled extras need separate review | Desktop Python/Qt application. No maintained Android embedding path was established | Not run or selected. Do not package a desktop `ebook-convert` process in the Android app or require a new server service to make MOBI fit |

Readium's documented PDF adapter uses an additional PDF engine.
Its presence does not establish extracted-text reflow.
The existing `PdfPage.loadText()` API supplies text and rectangles.
Its structured-text helper also analyzes direction and lines, but this research does not establish general column or table correctness for that helper.

The Python tools are research dependencies, not proposed Android app dependencies.
These include ReportLab, Pillow, Python Markdown, lxml, bleach, and Poppler utilities.
Poppler generates inspection images and a comparison extraction.
It is not the proposed Android PDF engine.

## Hard-path findings

### MOBI conversion

The experiment invokes libmobi's real source reconstruction and EPUB creation.
It does not rename a MOBI file to EPUB.
The output archives contain HTML and image resources, and the Dart parser reads them back.
Alice's source metadata identifies MOBI version 8, compression type 2, encryption type 0, and calibre 9.5.0 as its creator.

Supported proof variants are uncompressed MOBI6, PalmDOC-marked MOBI6, and PalmDOC-compressed standalone KF8.
HUFF/CDIC compression, hybrid files, Windows-1252 books, dictionaries, fixed-layout variants, and AZW4 remain unproved.
KFX and encrypted books are not included.
File extensions alone cannot establish the variant.
The eventual importer must inspect the file and reject unsupported or encrypted content without deleting the original.

Keep each original edition immutable.
Cache a conversion under its original file hash and converter version.
Store reading positions against that cached edition, not a percentage of an unrelated audio edition.
If the converter changes its output, retain the old conversion or explicitly migrate the text anchor.
Do not silently apply an old converted-document position to newly generated chapter structure.

The native parser handles untrusted bytes.
An isolate, Dart's background execution unit, prevents UI blocking but does not isolate a native crash.
Memory limits, input limits, fuzz testing, crash containment, and malformed-file handling remain release work.
The stale upstream release increases that burden.

### PDF text order and headings

The column fixture draws each right-column line before its left-column line.
The proof groups characters by their source baselines and horizontal gaps.
It then orders the two columns by geometry rather than draw order.
The result is the title, three left-column lines, then three right-column lines.

The same heuristic loses the table fixture's row relationships.
This is direct evidence against promising universal PDF reflow.
Font-size-based heading candidates also lack semantic certainty.
The proof does not read tagged-PDF structure trees or recover missing character maps.
It also retains source line boundaries as separate text blocks.
Paragraph reconstruction, hyphenation repair, footnotes, and inline picture placement are not implemented.

Use original-page rendering as a permanent alternative.
Keep reflow optional and available only when extracted text exists on the relevant source page.
Do not manufacture empty text pages for a scan.
Do not hide original pages behind a promise that every extraction is readable.
Mixed text/scan PDFs require a per-page result, not one document-wide success flag.

### Page-to-text anchors and phone-width reflow

An anchor identifies text independently of the current line wrapping.
The proof records the original file's SHA-256, source page, PDFium character index, and character rectangle.
It restores the phrase after layouts at two widths.
It rejects the anchor when the original file bytes change.

The source page numbers in the Python proof start at zero.
The source character index comes from `FPDFText_CountChars` and related PDFium APIs.
The Dart package exposes text indices and character rectangles through its own API.
Do not assume those index units match for all Unicode text.
The samples establish that relationship only for their ASCII text.

Production positions also need an extraction-version identifier and quote context.
The extraction-version identifier distinguishes changes in the engine and layout interpretation.
Quote context supplies nearby text for a checked migration when character indices change.
These additions are a recommendation, not implemented sync or migration behavior.

The reflow proof draws 18-point body text at an unchanged font size.
It wraps that text in 328 points of content width inside a 360-point page.
A 720-point page uses fewer lines at the same font size.
Both outputs contain newly laid-out extracted text, not resized source-page images.
The 360-point document is a host layout surrogate for a narrow phone viewport.
It is not an observed Android screen, CSS pixel measurement, or Flutter font-scale test.
The measured line counts are 10 at 360 points and 8 at 720 points.

Original-page scaling also exposed a real API trap.
The first call set the render area's width and height, which cropped the source page instead of scaling it.
A test of a marker near the source page's bottom-right corner failed because the marker was missing.
The corrected call from the Dart proof is:

```dart
        final image = await page.render(
          fullWidth: 360,
          fullHeight: page.height * 360 / page.width,
        );
```

where

- `page` = the source PDF page object, 612 by 792 PDF points in this scan fixture.
- `page.render()` = the package operation that renders the source page into an image.
- `fullWidth` = the output width of the whole source page, in pixels.
- `fullHeight` = the output height of the whole source page, in pixels before integer rounding.
- `page.width` and `page.height` = the original page dimensions, in PDF points.
- `image` = the returned image object, or null if rendering does not produce one.

The corrected call preserves the page's shape and the bottom-right marker.
The expected-failure log is `evidence/crop-red.txt`.

### Scans and OCR

The scan fixture has only image pixels and no PDF text layer.
PDFium returns no extracted text, while its original-page renderer returns visible pixels.
That page requires OCR for text reflow.
OCR means recognizing words from an image.

No OCR engine or language model was installed or selected.
OCR accuracy, language downloads, battery cost, storage, licensing, and new text anchors require separate scope approval.
Original-page fallback already fits the approved plan.
This research does not add an OCR subsystem to `boo-mx5i`.

## Passive HTML and local resources

The proof parses HTML before filtering it.
It keeps a small set of reading elements and attributes.
It removes scripts, styles, frames, forms, SVG, embedded objects, event handlers, and network URLs.
It resolves each local asset under the book directory after percent decoding and path normalization.
It rejects parent traversal, absolute filesystem URLs, and remote image references.
The tests also require legitimate local images and internal links to survive.

This restrictive proof discards author CSS.
It does not establish production typography or complex EPUB fidelity.
Its Python sanitizer is not proposed as an Android runtime dependency.
Port the boundary into the chosen Android reading path and test that actual path.

Before production, enforce these properties in the Android content boundary:

1. Bound archive entry counts, expanded bytes, nesting, and decoded image sizes before import.
2. Reject escaping archive paths, symlinks, and ambiguous encoded asset paths.
3. Serve only immutable, imported assets under a private book origin.
4. Block remote resource requests at the request boundary, not only in markup.
5. Block publisher scripts, dangerous navigation, external fonts, frames, and active SVG.
6. Apply a restrictive Content Security Policy and disable unused WebView file and content access.
7. Keep any reader-owned JavaScript separate from publisher JavaScript.

Readium uses reader-owned JavaScript for navigation.
Do not assume disabling all JavaScript preserves its navigator.
Its integration needs an explicit publisher-content policy and request tests.
Network policy remains owned by Bookfin, not by a book's markup or an external viewer.

## Native size and Android evidence

The cross-build uses Android NDK 28.2.13676358 and targets API 24 with `arm64-v8a`.
The Android PDFium artifact is a pinned upstream prebuilt, not a PDFium source build by this ticket.
The libmobi library is built from the pinned source.
The link probe calls both libraries' real APIs and links with unresolved symbols forbidden.

| Artifact | Exact bytes on disk | What the result establishes |
| --- | --- | --- |
| Stripped Android `libmobi.so` | 161,152 | C parser and source reconstruction compile for ARM64, with no external XML library or DRM code |
| Android `libpdfium.so` | 6,598,376 | ARM64 original-page and text-extraction engine is available |
| Android `libbookfin_reader_probe.so` | 7,976 | Both native APIs link together without unresolved symbols |

Both engine libraries have 16,384-byte load-segment alignment.
Their inspected dynamic dependencies are Android system libraries, not a separately bundled C++ runtime.
This does not establish runtime correctness on a 16-KiB-page Android device.
The counts above are uncompressed shared-library sizes, not APK growth or installed-app size.
They exclude Flutter, Dart code, reader UI, caches, conversion output, and additional ABIs.

The cross-build script saves ELF headers, dependencies, and alignment in `_out/android-linkage.txt`.
ELF is Android's native binary file format.
The probe is a link check, not an Android execution test.
No native method, lifecycle event, memory-pressure case, or on-device reading gesture was observed.

The first isolated APK attempt exposed a real SDK dependency.
The transitive `jni` Android plugin fixes its compile SDK at 35.
The shared project SDK has only platform 36, and Gradle cannot add platform 35 to the immutable Nix store.
The research `#android` dev shell adds platforms 35 and 36 without changing the shared flake or SDK.
The isolated APK script never installs or launches its output.
The isolated ARM64 debug APK builds successfully with pdfrx 2.11.0.
Its archive contains `libmobi.so`, `libpdfium.so`, the PDFium gate library, and the generated PDF asset.
This proves Flutter/Gradle packaging, not execution of that APK.
The observed debug APK is 101,298,494 bytes.
Its size includes Flutter's debug engine and validation library, not only reader code.
The transitive JNI package also includes small ARMv7 and x86-64 libraries despite the ARM64 build target.
Do not use this whole debug artifact as an estimate of release APK growth.
The APK digest and native-entry inventory are in `evidence/observations.json`.
Both packaged engine digests match the pinned native proof files byte for byte.
The Dart native-asset hook downloads its own binary during a clean build.
This comparison establishes the inspected APK's engine provenance despite that separate download path.
Production must retain hash verification and an explicit build-time supply policy.
The APK's 16-KiB ZIP-alignment check also passes.

## Redistribution gates

This is an engineering inventory, not legal approval for a particular distribution model.
Read the pinned licenses before release.
Do not infer a native engine's obligations from a Flutter wrapper's license.

For PDFium, retain its BSD-style notice and all applicable bundled component notices.
Retain the binary-builder license too.
The inspected archive includes those files under `LICENSE` and `licenses/`.
The inspected non-V8 build excludes JavaScript execution and XFA, the XML Forms Architecture.
This does not remove the need to restrict external actions in the app.

For libmobi, the LGPL permits some combinations with non-LGPL application code, subject to conditions.
Keep the library notices, LGPL/GPL license texts, source availability, and modification information required by the license.
Use a replaceable shared-library arrangement or supply the application material needed for relinking under the applicable terms.
Do not prohibit the reverse engineering needed to debug modifications to the library.
Review installation-information requirements when they apply.
An Android `.so` filename alone does not prove compliance with those conditions.

MuPDF introduces a different choice: satisfy AGPL terms for the combined distribution or obtain a commercial agreement.
No commercial price, permission, or closed-source exception is established here.
Do not select it merely because one API looks convenient.

The research binaries and generated APK are local proof artifacts, not release packages.
The release pipeline still needs a complete notice bundle and a license inventory for locked transitive dependencies.

## Recommended implementation path

Keep one imported-edition model.
An imported edition contains an immutable source, a reproducible derived reading document when needed, and source-aware positions.
Changing font size changes layout, not the saved source location.
Changing source bytes creates a different edition identity.

1. Use pdfrx/PDFium for original PDF pages and the extraction boundary proved here.
2. Implement optional text layout with source-page anchors. Preserve original-page access for scans and bad extraction.
3. Keep MOBI conversion behind one importer. Evaluate libmobi only after license policy and maintenance-risk review.
4. Convert supported MOBI locally to a cached reading document. Never require calibre or a new server for ordinary reading.
5. Evaluate Readium's maintained EPUB navigator through a narrow Android bridge before selecting the production EPUB package.
6. Feed HTML and Markdown through the same passive-content policy as imported EPUB content.
7. Keep reader locators, PDF source anchors, and audio milliseconds distinct within the approved edition model.

epubx is a useful feasibility probe but not the recommended parser dependency for the current app.
Its old dependency ranges conflict with the current PDF engine package.
Do not resolve that conflict with an unchecked dependency override.

## Decisions and remaining acceptance

The approved plan already permits optional PDF text reflow, original-page fallback, and a separate OCR decision.
Those items do not require a new product fork to continue the reader tickets.
The following remain explicit gates rather than silent scope reductions:

| Gate | What must happen | Owner |
| --- | --- | --- |
| Actual book compatibility | Obtain the user's unencrypted MOBI and PDF examples and run this corpus plus the resulting reader | Parent and user |
| Native license policy | Accept the LGPL distribution work, or choose another licensed converter before shipping MOBI | Parent and user if policy is unsettled |
| EPUB package | Prove the chosen maintained navigator with Flutter, local assets, fonts, and stable positions | `boo-9wgg` |
| Shared SDK prerequisite | Add platform 35 for the reader's transitive JNI dependency without modifying a user SDK | Follow-up `t9-26f6` |
| PDF pictures in text mode | Prove or explicitly choose how pictures appear in reflow. This proof is text-only | `boo-mx5i`, with user choice if scope changes |
| Unproved MOBI variants | Test representative HUFF/CDIC, hybrid, legacy-encoding, and malformed inputs before claiming them | `boo-mx5i` |
| Android runtime | Load both libraries and exercise local rendering, extraction, restart, anchors, and memory pressure on the assigned device | Reader owner in a later device wave |
| Release hardening | Fuzz untrusted input and complete coverage, mutation review, notices, and source/relink material after acceptance | Orchestrator and `boo-gk92` |

If PDF picture handling becomes a real product fork, present these two designs to the user before building it:

| Design | Picture result | Implementation cost | Usage example |
| --- | --- | --- | --- |
| Text reflow with original-page links | Pictures remain on their intact original pages. Text positions retain the source page | Lower cost. Switching views is necessary to inspect a picture | Read a paragraph, then open its source page to inspect the diagram |
| Interleaved text and extracted pictures | Reflow places recovered pictures between extracted text blocks | Higher layout and testing cost. Columns and captions still need fallback | Read a paragraph, then inspect the extracted diagram in the reflow stream |

Both designs retain original-page rendering, source-aware positions, and a fallback for uncertain extraction.
Neither design adds OCR or audio/text alignment.
This research selects neither design for the user.

## Reproduce

Run commands from the checkout root on `aarch64-darwin`.
The first run downloads Nix tools and public packages.
The external sample's original bytes are versioned with the fixture corpus.
Engine calls and reading samples use local files after preparation.
No network-denial test ran, so do not describe this as measured network isolation.

```sh
nix develop ./tool/research/readers --command bash tool/research/readers/run
```

This runs nine Python tests, three Dart PDF/Markdown tests, and four Dart EPUB/conversion tests.
It also writes converted EPUBs, original-page images, reflow PDFs, sanitized HTML, and `_out/report.json`.
The output directory is ignored by Git.
The generated fixture files are committed, and the generator can recreate them.

For the native Android build, use the existing project NDK without any emulator action:

```sh
nix develop --command bash -c 'export BOOKFIN_NDK="$ANDROID_HOME/ndk/28.2.13676358"; nix develop ./tool/research/readers --command bash tool/research/readers/android-build'
```

For the isolated Flutter APK packaging check:

```sh
nix develop ./tool/research/readers#android --command bash tool/research/readers/android-apk
```

The generated application remains under `tool/research/readers/_out/flutter-smoke/`.
The script does not invoke adb, agent-device, or an emulator.
The committed smoke template and dependency lock belong only to research.

To reproduce the incompatible Dart dependency combination:

```sh
nix develop ./tool/research/readers --command bash -c 'cd tool/research/readers/solver_conflict; dart pub get --offline'
```

That command is expected to fail dependency resolution.
It does not test reader behavior or indicate failure of the independent proof packages.

The default research shell includes a small `xcrun` adapter for Dart native build hooks.
It returns the pinned Nix macOS SDK location, not a system SDK or invented iOS SDK.
The stock Nix `xcrun` fails the hook's lowercase `macosx` query.
The hook also strips the shell's SDK environment, so the adapter embeds the Nix SDK path.
This adaptation changes neither the user's profile nor the shared toolchain.

## Primary sources inspected

Sources were fetched directly from their repositories or package archives on November 1, 2026.
Package source and license observations refer to the named versions, not an assumed latest release.

| Source | Evidence used |
| --- | --- |
| https://github.com/bfabiszewski/libmobi/tree/v0.12 | Parser capabilities, public C API, CMake build, LGPL license, release metadata |
| https://api.github.com/repos/bfabiszewski/libmobi/commits?per_page=1 | Inspected default-branch commit `906274205c11944b628da1c553b255acb1af7c55`, October 29, 2024 |
| https://github.com/bblanchon/pdfium-binaries/releases/tag/chromium/8125 | Host and Android binary archives, build flags, PDFium version, license bundle |
| https://pdfium.googlesource.com/pdfium/+/refs/heads/main/public/fpdf_text.h | Source text, Unicode, font-size, and rectangle APIs. Matching headers are in each pinned binary archive |
| https://pub.dev/packages/pdfrx/versions/2.11.0 | Flutter wrapper and its package requirements |
| https://pub.dev/packages/pdfrx_engine/versions/0.9.0 | Local-file API, text rectangles, rendering API, structured-text helper, MIT license |
| https://pub.dev/packages/pdfium_dart/versions/0.4.1 | Build hook, chromium/8125 download, FFI bindings and native assets |
| https://pub.dev/packages/pdfium_flutter/versions/0.4.1 | Flutter platform packaging and Dart/Flutter minimum versions |
| https://github.com/readium/kotlin-toolkit/tree/3.4.0 | BSD license, EPUB/PDF format matrix, Android requirements and PDF adapter guide |
| https://pub.dev/packages/epubx/versions/4.0.0 | MIT license, parsing API, dependency constraints, publication date |
| https://pub.dev/packages/markdown/versions/7.3.0 | Markdown conversion API and license |
| https://github.com/ArtifexSoftware/mupdf/blob/1.27.0/COPYING | AGPL alternative. No binary test performed |
| https://mupdf.readthedocs.io/en/latest/license.html | Dual-license policy reference. Obtain actual commercial terms separately |
| https://github.com/kovidgoyal/calibre | Desktop converter source and license alternative. No binary test performed |
| https://www.gutenberg.org/ebooks/11 | External KF8 source, public-domain status in the United States, and ebook terms |
| Pinned nixpkgs `pkgs/by-name/mu/mupdf/package.nix` and `pkgs/by-name/ca/calibre/package.nix` | Reproducible alternative versions 1.27.2 and 9.15.0 without installing them |
