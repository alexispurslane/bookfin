# OCR review corrections

This is implementation and host verification evidence for `boo-suhu`.
It is not Android OCR acceptance or distribution approval.
All four review findings are accepted and corrected. None is rejected.

The correction boundary starts at `acd233323d06b7ea5e23969278c46c44bfd6758c`.
The original implementation base is `2d43820`.
The prior APK source `5fca4a2` is superseded, not accepted.
The format admission from parent `44d53af`, imported as `78ce699`, remains unchanged.
The correction does not edit the parent checkout or its artifacts.

## Findings and proof

| Finding | Meaningful failure | Correction and green verification |
| --- | --- | --- |
| F1 | `red-text.txt`: mixed textual classes lose the heading, floating text and caption. A heading-only page returns empty text. Alternate columns return absent rather than conservative fallback. Nested lines publish rather than reject. | One decoder accepts the four pinned textual line classes. Nested lines and nested words fail conservatively. `pinned-line-classes.txt` identifies the exact source locations in the pinned archive. The focused tests retain the existing column and fragmentation checks. |
| F2 | `red-text.txt`: the second text request returns the unreliable extracted layer after explicit successful recognition. `red-search-initial.txt`: actual search reports one skipped source page instead of the recognized match. `red-selected-memory.txt`: failed cache saving lets the second request replace “garden” with “meadow.” | The document-owned recognition supply retains explicit intent and a bounded working set of selected results. Verified cache restores the selection on reopening. Every reuse still verifies the original and uses the existing download ownership interval. Actual search and revisit retain the selected text. |
| F3 | `red-position.txt`: the real record owner receives page two, character zero, instead of the saved page-two character ten after empty, failed or canceled recognition. Changed text/model and legacy positions incorrectly reflow. Changed policy discards the source-page address. | The document owns text representation identifiers and address resolution. The viewport preserves unresolved addresses and displays their original source pages. Final tests use the real SQLite record owner, close and reopen its database, and construct a new reader session. Missing and corrupt caches, empty/failed/canceled recognition, text/model/policy changes and legacy addresses retain page two. Compatible nonzero reflow and intentional source-page navigation still work. |
| F4 | `red-worker.txt` and `red-worker-all-boundaries.txt`: held native initialization, recognition and close errors leave operation or close futures pending until the test times out. `red-fatal-channel.txt`: the reader describes fatal native failure as retriable. `red-fatal-viewport.txt`: the viewport still offers recognition retry after a fatal worker. | Admitted work and close futures settle with the original error. Fatal or unsafe cleanup closes the worker and blocks later admission. Safe `IOException` failures still retry. Suppressed cleanup failures and the global engine permit remain observable. The channel and viewport require restart rather than offer unsafe recognition retry. |

The original red widget harness used a fake test clock around real native I/O.
Some early attempts stalled while draining later work and were interrupted.
`red-search-initial.txt` retains the meaningful first search assertion from such an attempt.
Do not treat its interrupted later drain as a production failure or a completed test run.
The final harness pumps frames while native work settles and closes every document.
`red-position.txt` then demonstrates the position failures without a stalled command.
Its earlier foundation-variable warning is not counted as proof for any finding.
The final harness removes that override.

## Final host checks

Commands run one at a time through the pinned Nix development shell.
The host load was checked before heavy commands.

| Evidence | Result |
| --- | --- |
| `focused-green.txt` | 53 focused reader tests pass. This includes actual PDFium rendering and the selected English-fast model through the real host Tesseract executable. |
| `full-tests.txt` | `bash tool/bookfin test`: 474 tests pass, three opt-in tests skip. SDK link, Android SDK 35/36 compilation, Darwin native hooks, and native-worker checks also pass. |
| `analysis.txt` | `bash tool/bookfin analyze`: no issues. |
| `green-worker.txt` | Held engine tests cover fatal initialization, operation, close and cleanup, unsafe admission, safe I/O retry, preserved errors and engine-permit release. |
| `source-hashes.json` | SHA-256 values bind the changed production and test files to this evidence. Preserved format-admission blobs match the correction base. |

The skipped tests are the bounded journal-growth measurement and two live Jellyfin
plugin integration or upgrade tests. This task starts no server or live service.
Expected negative-fixture diagnostics in the SDK/native-hook checks are not failures.
Flutter reports unavailable iOS SDKs on this Android-focused host. Host tests pass.

The host engine is Tesseract 5.5.3 with Leptonica 1.87.0.
The APK uses the pinned Tesseract 5.5.1 and Leptonica 1.85.0 libraries.
The exact English-fast model hash is
`7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2`.
The complete generated-English reference matches after whitespace normalization.
This does not establish historical-scan accuracy or Android recognition behavior.

## Packaging and remaining gates

`HANDOFF.md` records the completed package verification, exact artifacts and the
distinction between the clean APK source commit and the later evidence commit.

Commit the corrected source before exporting its exact source and building the normal APK.
The later package verification and provenance identify the APK source commit separately
from the commit that records packaging evidence. They bind the APK, exact Git archive,
pinned sources/model/licenses, verification reports and build logs by SHA-256.

Normal-app Android OCR acceptance remains open. It still requires fresh-install offline
recognition, navigation/search/reflow, cached reopening, cancellation, account/source/removal
changes, failure/retry, memory/latency measurements and approved reader-layout inspection.
Existing PDFium/libmobi distribution, replacement, source-delivery, signing/store and
installation-information decisions remain open. Obtain the parent distribution decision
and qualified compliance review before release.

No device, adb, installation, UI action, fixture port, server, live service, acceptance,
coverage campaign, mutation campaign, ticket closure, PR or publication belongs to this run.
