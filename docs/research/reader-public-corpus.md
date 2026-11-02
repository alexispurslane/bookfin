# Public reader corpus: November 2, 2026

This continues `boo-73yj` from main `756ae5f`, after the integrated `09c2081` corrections.
It adds host evidence to [reader-formats.md](reader-formats.md), without replacing its earlier observations.
The source manifest is `tool/research/readers/corpus-manifest.json`.
It records exact input URLs, SHA-256 fingerprints, byte counts, expected features, rights statements, and territorial limits.
A fingerprint identifies the exact file bytes, not just its title or download URL.

Nine distinct works and documents total 7,427,757 bytes.
Each source is below 16,000,000 bytes.
Acquisition rejects more than ten sources or 32,000,000 total source bytes.
Downloads have a 90-second limit and use public HTTPS URLs without credentials.
The source files and full derived books remain in ignored `_out/corpus/`.
No committed fingerprint fixture was regenerated or changed.

## Corpus and observed results

The year below is the work or document's publication year, not the downloaded file's creation year.
An EPUB spine is the ordered list of resources that make up its reading text.
Dart text lengths use UTF-16 code units; Python text lengths count Unicode code points.
The recorded lengths are not a cross-engine equality claim.
A successful phrase check establishes that the sampled words survived parsing.
It does not establish typography, readable PDF order, navigation, accessibility, or saved positions.

| Source work or document | Input bytes and format | Observed result | Limit |
| --- | --- | --- | --- |
| Lewis Carroll, *Alice's Adventures in Wonderland* (1865), Gutenberg 11 | 189,249; EPUB3 | Patched EPUBX reads 15 spine resources. Opening/later text and one JPEG cover survive. Local resource and fragment checks find no missing targets | This particular download has a cover, not inline illustrations. The endpoint name does not prove illustrated content |
| Mary Shelley, *Frankenstein* (1818), Gutenberg 84 | 519,544; MOBI6 | Internal version 6, UTF-8, PalmDOC compression type 2, encryption type 0. libmobi converts it to EPUB2. Dart reads opening and final text and two JPEG resources | The converted spine contains one long XHTML resource. That is not conversion failure or evidence of chapter navigation |
| Herman Melville, *Moby Dick* (1851), Gutenberg 2701 | 1,232,584; KF8 | Internal version 8, UTF-8, compression type 2, encryption type 0. Converted EPUB2 has 144 spine resources, two JPEG resources and one SVG resource. Opening text and epilogue survive | The SVG repeats the resource-type issue in `t3-9r9u`. Parsing it is not an Android image-rendering result. No hybrid KF7/KF8 or HUFF/CDIC input was acquired |
| Voltaire, *Candide* (1759), Gutenberg 4650 | 195,063; French EPUB3 | Dart reads 36 spine resources. `Pangloss` and accented `était` survive. A PNG cover decodes | No bidirectional text, non-BMP character, embedded font, or complex-script claim |
| Bram Stoker, *Dracula* (1897), Gutenberg 345 | 728,707; HTML ZIP | The existing passive-content filter retains all 33 headings and both local image references. It retains 27 of 32 links and removes both style elements | External links and publisher CSS are deliberately discarded. This is a host filter, not Android network interception or a visual reader |
| William Shakespeare, *Sonnets* (1609), Gutenberg 1041 | 119,936; UTF-8 text used to derive Markdown | The complete text, including Gutenberg terms, becomes one fenced text block under a Markdown heading. Pinned Dart Markdown preserves the sonnet-18 phrase and adjacent verse line breaks | This is an openly documented serialization of a real work, not a publisher-authored Markdown edition. A code block does not prove general poetry layout |
| Mell and Grance, NIST SP 800-145 (2011) | 85,781; tagged text PDF, seven pages | PDFium extracts all seven pages. Source page 5 renders through Dart and supplies a source-page character anchor. Its extracted text survives both host reflow widths | The proof does not consume the PDF tag tree, rebuild paragraphs, preserve the introduction banner, or validate footnote associations |
| Census Scientific Advisory Committee; Request for Nominations, Federal Register (2024) | 186,352; two three-column PDF pages | PDFium extracts text and Dart renders the sampled original page. Known phrases and a source anchor survive | The geometry proof combines unrelated columns and adjacent notices into lines. This is an observed fidelity failure, despite successful conversion and complete character retention |
| Edgar Allan Poe, *The Raven*, Doylestown printing (1873), Library of Congress | 4,170,541; 24 scanned PDF pages | Original pages render. The existing text layer yields text, but sampled page 9 becomes 37 short fragments with wrong poem order | This download already contains a text layer. No OCR ran here. Nonempty text does not establish readable reflow |

The Markdown derivation normalizes line endings and adds fences; its original downloaded text remains unchanged.
All four EPUB/conversion outputs have complete local targets for the checked HTML links, image paths, and fragment identifiers.
The check does not establish CSS URL safety, navigation behavior, or rasterization of SVG.
Both JPEG resources in each MOBI conversion and the EPUB covers decode with the pinned Pillow dependency.
The earlier generated image fixtures remain the separate PNG/inline-image proof.
No production navigator or dependency changed.
Engine binaries and package locks are pinned; this is not a claim of identical font fallback or page pixels on every host.

### What the failures mean

The Federal Register source has three columns, including the end of a USDA notice beside the Census notice.
Visual inspection of the retained source page confirms those separate columns.
The existing geometry proof joins words from those columns into single text blocks.
One resulting line is:

```text
identity (including gender expression), (Census Bureau) requests nominations with the provisions of the FACA.
```

The character-retention check still passes because the text is already misordered before reflow.
It compares reflow with extracted text, not with a human reading of the original page.
This demonstrates why exit status, phrase presence, source anchors, and character counts cannot establish PDF fidelity.
Follow-up `t0-odcl` records this gap without selecting a new layout algorithm.

The Raven source page visibly contains an engraving, the title, and the opening verse.
Its pre-existing text layer and the geometry proof yield fragments such as `NCE`, `upon`, `midnight`, and `nearly napping,` in the wrong order.
The image remains readable while extracted text is unsuitable as a faithful reading view.
The source text layer misses the opening `O` in `ONCE` and misreads the decorative title.
Poppler's layout-preserving extraction retains much of the verse order; the geometry proof further fragments it.
The retained Poppler output distinguishes source text errors from additional ordering errors in this proof.
This does not mean that all existing text on the scanned pages is unusable.
No extracted block on that sampled page exceeds the probe's 20-character anchor-candidate threshold.
The recorded anchor result is therefore null, not a failed navigation action.
Follow-up `t0-qnnu` records the need to handle unusable existing text separately from absent text.

The initial EPUB observation expected more than one spine resource for every book.
Frankenstein disproved that assumption: its opening and final text share one resource.
The retained initial log records the failed assumption.
The final checks require a nonempty ordered spine and both expected phrases, not artificial chapter-file splitting.
No converter or parser implementation changed to hide the observation.

### Host reflow measurements

A PDF point is one seventy-second of an inch in the source coordinate system.
The host proof keeps body text at 18 PDF points and lays text out at widths of 360 and 720 PDF points.
The values below come from ReportLab paragraph heights divided by line spacing.
They are not measured Flutter lines, screenshots of Android, or new claims about the earlier corrected widget.

| Sampled source page | 360-point width: derived lines | 720-point width: derived lines | Nonspace characters retained at both widths | Fidelity judgment |
| --- | --- | --- | --- | --- |
| NIST page 5 | 70 | 49 | 1,767 of 1,767 | Readable sampled prose; source line breaks remain separate blocks |
| Federal Register page 1 | 241 | 220 | 5,748 of 5,748 | Unreadable cross-column combinations remain |
| Raven page 9 | 37 | 37 | 174 of 174 | Short fragments preserve neither verse order nor image placement |

Poppler independently reads back both generated layouts.
After whitespace removal, their text exactly matches the already-extracted source blocks.
This checks for additional text loss during host layout, not correct extraction or human reading order.
The PDF source anchors resolve on the sampled NIST and Federal Register pages.
These are source-file/page/character lookups, not persisted reader resume positions.

A second Raven input is derived from the real page-9 scan.
The script renders that page at 720 pixels on its long edge and wraps only that image in a new PDF.
It does not copy the source text layer.
PDFium then reports zero text blocks, while the pinned Dart renderer still produces visible pixels.
The derivative's hash, size, source page, and derivation are recorded separately.
It is not passed off as an unmodified repository download.

### Malformed bytes and bounded acquisition

Two deliberately truncated copies exercise rejection without changing any original.
The first 96 bytes of Frankenstein produce libmobi exit 1, `Corrupted data`, and no EPUB.
The first 512 bytes of the NIST PDF produce exit 1 and `PDFium could not open the PDF`.
These are two finite host observations, not fuzzing, native-crash containment, or a malformed-file security guarantee.

Running the original and new PDF test files together initially aborted the host process with exit 134.
The exact error was `Cannot invoke native callback from a different isolate.`
The retained stack includes PDFium font mapping and page loading.
A native callback lets compiled engine code call Dart.
Each file had initialized the engine in a separate Dart test isolate, which is an independent Dart execution context.
The PDF research package now runs test files one at a time through `dart_test.yaml`.
The same eight checks then pass together.
This is a host test-execution remedy, not proof of a safe concurrent production engine.
Follow-up `t0-ebxa` records native callback ownership and lifetime as an explicit gap.
No Android callback or concurrency result is inferred.

The illustrated Pride and Prejudice download at `https://www.gutenberg.org/ebooks/1342.kindle.images` exceeded the initial 16,000,000-byte acquisition ceiling.
Curl rejected it with exit 63 and `Maximum file size exceeded`.
No oversized or partial Pride source is included in the final nine-source corpus.
Frankenstein supplies the real legacy-MOBI case instead.

The acquisition tests first failed because changed, incomplete, and oversized candidates were accepted.
They also caught replacing a retained original before verification.
All six tests now pass.
An existing local source is verified and rejected on mismatch, not silently refreshed or assigned a new fingerprint.
The new acquisition helper is research tooling, not Bookfin's production download manager.

## Source rights and territorial boundaries

The six Gutenberg catalog pages state `Public domain in the USA.`
Their URLs are in the manifest, and their downloaded source-page fingerprints are in `evidence/corpus/source-provenance.json`.
The ebooks retain Gutenberg's license and trademark terms.
These observations do not establish the same copyright status in every country.

The Library of Congress item is `https://www.loc.gov/item/unk82092576/`.
Its JSON rights field declares the collection's books public domain and free to use and reuse.
The retained derivative credit is Library of Congress.
This records the repository statement rather than an independent worldwide rights determination.

The NIST source is `https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-145.pdf`.
Its sampled introduction itself states that the guideline is not subject to copyright and requests attribution.
NIST's policy is `https://www.nist.gov/open/license`.
That policy distinguishes federal employee work, standard reference data, contractor work, and possible foreign protection.
The report identifies its NIST authors; this research does not infer clearance for unrelated NIST products.

The Federal Register notice is an official Census Bureau government notice.
The downloaded page also contains adjacent USDA government text.
GovInfo's policy at `https://www.govinfo.gov/about/policies` explains the US government-work basis and warns about separately protected material in some government publications.
The manifest records that qualification rather than declaring all GovInfo files unrestricted.
No engine redistribution compliance or release legal approval follows from these corpus-source observations.
The libmobi redistribution and replacement gate remains `t3-ipk1`.

## Reproduction and exact checks

Run from this checkout's root on `aarch64-darwin`.
Use the existing locked research Nix shell only.
The initial commands acquire inputs and prepare the same engines and compatibility patch used by earlier research.
They do not regenerate fixtures, build Android, or use a device or browser.

```sh
nix develop ./tool/research/readers --command bash -c '
  set -euo pipefail
  cd tool/research/readers
  python corpus_inputs.py
  bash run --keep-fixtures
  bash epub-compat
  export PDFIUM_LIBRARY="$PWD/_out/pdfium-host/lib/libpdfium.dylib"
  python corpus_probe.py
'
```

If an upstream download changes, acquisition fails its exact size or SHA-256 requirement.
Do not repin a changed source merely to make a reproduction pass.
Review its new rights and content first, and record a separate corpus revision.
To inspect only existing downloads, run `python corpus_inputs.py --verify-only` inside the same Nix shell.

The complete final host check runs 38 tests: 17 Python and 21 Dart.
The real-corpus tests are existing-engine characterization checks, not new production feature implementations.
Their explicit opt-in keeps the original fixture-only suites independent of network acquisition.
The six acquisition checks supply the new red-green behavior evidence.

```sh
nix develop ./tool/research/readers --command bash -c '
  set -euo pipefail
  cd tool/research/readers
  export PDFIUM_LIBRARY="$PWD/_out/pdfium-host/lib/libpdfium.dylib"
  export BOOKFIN_REAL_CORPUS=1
  python -m unittest -v test_readers test_run_inputs test_corpus_inputs
  for package in dart_pdf dart_epub dart_compat; do
    (cd "$package"; dart pub get --enforce-lockfile; dart test --reporter expanded)
  done
'
```

The counts are nine original Python checks, two runner-input checks, six acquisition checks, eight PDF/Markdown Dart checks, four original EPUB Dart checks, and nine joint-parser Dart checks.
This does not rerun the separate native bridge or Flutter widget suites from the earlier 30-test correction checkpoint.
The correction's prior evidence remains unchanged.
Nonfatal Dart build-hook messages say that iOS SDKs are unavailable; no iOS target is claimed.

Committed evidence is under `tool/research/readers/evidence/corpus/`.
It includes machine-readable extraction and parser observations, source provenance, input preservation, red/green acquisition output, final test output, and small lawful source/reflow previews.
Full originals, converted books, generated PDFs, native packages, and caches remain ignored.
`python-observations.json` includes hashes for each source and derived EPUB; `dart-epub-observations.json` records the actual parser's ordered resources.

No account, Jellyfin server, credentials, private library, Android app, device setting, browser, or public development server was used.
No production navigator, OCR engine, release license approach, coverage job, mutation job, subagent, PR, or ticket closure is part of this work.
The parent owns integration, follow-up ordering, production approval, and ticket closure.
