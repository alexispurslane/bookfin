---
id: boo-5ivg
status: closed
deps: []
links: []
created: 2026-11-12T23:41:02Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Decode the admitted EPUB record off the UI isolate at reopen

## Current-path audit and settled scope — 2026-11-13

Parent inspection at 2aab2d8b finds that AdmittedBooks.load already calls read inside Isolate.run, including Publication.decode, and returns the publication through worker exit. EPUB and MOBI production open paths use load. Other direct read callers document worker-only use for speech/search. The survey may therefore be superseded by integrated boo-yjq6/boo-sy2d work. Audit every real production reopen caller before changing code; do not build a second offload or speculative abstraction for a stale finding.

Required result: admitted-record header decode, validation, text-resource splitting and associated copies run outside the UI isolate, within the existing owned read/worker operation. Preserve immutable resource bytes, lazy binary ranges, digest/policy/revision checks, damaged-record retention and re-admission, download holds, pending record writes, EPUB/MOBI behavior, and returned publication semantics. If current code already satisfies the requirement, provide source provenance and meaningful existing or added boundary proof, and make no production change. If a real caller violates it, reproduce that path before the smallest fix through the same owner.

Verification must show the production reopen path uses worker execution and retains publication facts; use real saved records and controlled boundary evidence, not a wall-clock threshold or a test of an unused helper. Run admitted-books/publication/platform/MOBI and affected download/speech/reader checks, affected analysis/format, and the full Flutter suite through Nix at concurrency two, one heavy command at a time. No Android speed claims. Exactly one fresh read-only Astra high reviewer; implementation/direct fixes Astra xhigh. No devices, browser, coverage, mutations, push, PR, merge or closure. Parent integrates and closes. Avoid EPUB preparation/places/pager work owned by boo-hd47.

Original survey claim, disproved by the caller audit below: found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. The survey called it "confirmed on the UI isolate, size estimated": lib/reader/epub/publication.dart:243-268, called from lib/reader/admitted_books.dart:280. It estimated 2 to 10 MB of header/text work at reopen. That estimate was not measured here and the stated execution location was incorrect. Related: t6-0yez (measurement), t0-r8ii.

## Launch — 2026-11-13

Astra xhigh lead launched from e72d2335b1197080464e2381b923b9b310429da2; running, stage uncertain. One fresh read-only Astra high reviewer authorized. Audit existing production worker ownership before deciding whether implementation is needed.

- clientRequestId: bookfin-boo-5ivg-astra-20261113-1
- taskId: node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-5ivg-astra-20261113-1
- childThreadId: thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-5ivg-astra-20261113-1
- Link: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-5ivg-astra-20261113-1>

## Execution-boundary audit — 2026-11-13

Lead checkout: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-618c77bd`, branch `t3/offload-epub-reopen-decode`. Initial HEAD was the requested review base `e72d2335b1197080464e2381b923b9b310429da2`, with a clean index and worktree. No checkout was created, switched or reset. Ticket remains in progress for parent integration and closure.

No production change is needed. `AdmittedBooks.load` is the single owner of the reopen worker. Its `Isolate.run` awaits `read`, which awaits `_kept`, which awaits `Publication.decode` before closing the record handle. Header JSON decode and validation, the text block read, separate immutable text-resource copies, binary range construction and the returned publication all finish in that worker. The worker returns the result through `Isolate.run`'s exit transfer; there is no UI-side publication reconstruction or second offload. `Publication.decode` has exactly one production caller, `_kept`.

| Production entry or consumer | Record path and execution owner |
| --- | --- |
| ReaderSession's `loadReadingDocument`, EPUB | `platform_io._admitted` -> `_readAdmitted` -> `AdmittedBooks.load` -> its worker |
| ReaderSession's `loadPublication` | Same `_admitted` path; `main.dart` wires both reader loaders |
| `loadReadingDocument`, MOBI/AZW3 | `importMobi` -> serialized `readMobi` -> `AdmittedBooks.load` -> its worker; document construction after the return does not decode the record |
| Crossings' `measureDownloadedOutline`, EPUB or MOBI | `_readAdmitted` or `readMobi` supplies `measureTextOutline` to the same load worker |
| Download preparation, EPUB or MOBI | `prepareDownloadedBook` -> `AdmittedBooks.prepare` or serialized `prepareMobi`; `prepare` calls `read` and `keep` inside its own existing worker; its small current-key check uses asynchronous I/O |
| Speech/search EPUB words | `bookWordsReader` creates `_wordsOf(..., _keptOrAdmittedEpub)`; Crossings passes this reader to `BookSearch.withBook`; `KeptWorker._serve` invokes the job in the spawned worker, so the direct `AdmittedBooks.read` is worker-only |
| Speech/search MOBI words | Same `BookSearch` worker, with `keptMobi`; it reads the admitted record or kept conversion and writes nothing |
| Web platform stub | Throws or returns no reader; does not decode admitted records |

Repository-wide searches also checked tool consumers. `tool/reader/open_benchmark.dart` and the research Flutter reader use `loadReadingDocument`. Direct calls to `AdmittedBooks.read` outside the owner and the two speech helpers are tests. No production caller bypasses the execution owner.

### Provenance

- `8ba0ac4e820f6d13b7e5c5508891c2eb88a2c9bc` (t7-rcyp, November 9) introduced kept admitted records. Both platform EPUB and MOBI opens already wrapped the complete admitted-record open in `Isolate.run`.
- `8c54573abbef63626d9444a7ecbd3ff79e907112` (boo-yjq6, November 11) moved that worker ownership into `AdmittedBooks.load`, including `read` and the caller's publication use, and moved new-record writes after the load result.
- `18f253a98a9013e75dbed46ec9bef8ef3c984a65` (boo-yjq6) added the current lazy binary ranges and per-resource text copies inside `Publication.decode`, reached within that same worker.
- `bac5b648ad136b8ca498803268ebb0e2015497b8` retained new records when the worker's use callback throws.
- `8e659ae5c5a7e116676b3a9d02a19dae531667eb` (boo-sy2d/t4-3o9f) introduced held download preparation. `74aa8c3264ce362acd917a9768163d5bd023f190` retained this model in the subsequent review fixes.
- `5944606e5fa5b76a019f870a491ba322bc80100e` (boo-vh77 review) introduced `_keptOrAdmittedEpub` and `keptMobi` and removed their record-persistence calls, so speech readers cannot write after their download loan ends.
- Inspection of the survey's own `f9f26500e11de09adcbbe304e66cab162860c158` confirms the same `AdmittedBooks.load` worker. This was a caller-tracing error in the survey, not an outstanding regression on the assigned base.

### Saved-record proof

`test/reader/admitted_books_test.dart` now guards the actual production EPUB document, EPUB publication and MOBI document reopen paths. Each first opens real book bytes and waits for the saved record. The test then destroys the original archive bytes; the MOBI test also removes the conversion. A zone-local file guard refuses to open that saved record in the calling isolate. The production reopen succeeds using the real saved file in its worker, and the admitted facts match the first open. The publication-loader test also checks that returned text bytes remain immutable and an image's bytes remain available.

The guard's control test calls the actual `AdmittedBooks.read` in the calling isolate and observes the specific guard error, proving this observation detects a moved read. The guard detects the record-open boundary, not CPU time or individual copy instructions. Source tracing above establishes that decode, validation and splitting complete behind that boundary with the open file handle. No production hook, timing threshold, artificial slowdown or performance claim was added. Since production already meets the requirement, no implementation red/fix cycle or mutation was needed.

Existing admitted-book tests retain proof for changed digest/policy/revision, malformed/truncated records and unreadable retention, successful re-admission, delayed writes, failed writes, partial writes, download holds/removal, lazy image reads and changed-record rejection, and saved EPUB/MOBI places. Publication, MOBI, reader, download and speech suites supplement these checks. No EPUB prepare/places/pager code was changed.

### Verification and review

Evidence logs are saved under `/tmp/bookfin-boo-5ivg-evidence/`. All commands run from the lead checkout, with one build/test command at a time. No Android/device/browser work, coverage, mutation testing, push, PR, merge, closure or worktree deletion is part of this ticket lead's work.

| Exact command | Result | Log in the evidence directory |
| --- | --- | --- |
| `nix develop --command dart format test/reader/admitted_books_test.dart` | Exit 0, one file formatted. Initial fresh-checkout package resolution warning for `flutter_lints/flutter.yaml`; the following Flutter test resolved packages. | `format-write.log` |
| `nix develop --command flutter test --concurrency=2 --reporter=expanded test/reader/admitted_books_test.dart --name 'record-open guard\|outside the calling isolate'` | Exit 0, 4 passed, including the guard control. | `boundary.log` |
| `nix develop --command flutter test --concurrency=2 --reporter=expanded test/reader/admitted_books_test.dart test/reader/publication_test.dart test/reader/mobi_document_test.dart test/reader/unknown_format_test.dart test/reader/book_words_reader_test.dart test/reader/text_outline_test.dart test/reader/downloaded_reader_test.dart test/reader/session_native_test.dart test/downloads test/speech test/crossings/speech_landings_test.dart` | Exit 0, 453 passed. | `focused.log` |
| `nix develop --command flutter analyze lib/reader/admitted_books.dart lib/reader/epub/publication.dart lib/reader/platform_io.dart lib/reader/mobi.dart test/reader/admitted_books_test.dart` | Exit 0, no issues in 5 items. | `analyze.log` |
| `nix develop --command dart format --output=none --set-exit-if-changed lib/reader/admitted_books.dart lib/reader/epub/publication.dart lib/reader/platform_io.dart lib/reader/mobi.dart test/reader/admitted_books_test.dart` | Exit 0, 5 checked, 0 changed. | `format-check.log` |
| `git diff --check` | Exit 0. | `diff-check.log` |
| `nix develop --command flutter test --concurrency=2 --reporter=expanded` | Exit 0, 3,497 passed, 27 skipped, 0 failed. | `full.log` |

Flutter setup printed `xcrun` errors for absent `iphoneos` and `iphonesimulator` SDKs in the test logs; host tests still exited successfully. Dependency resolution noted 38 newer incompatible package versions; no dependency files changed. Full-suite skips are the repository's optional corpus, benchmark and external-environment checks; their skip messages are retained in `full.log`. No failed or interrupted top-level commands occurred. No benchmark flags were enabled, and no timing or Android claim follows from these results.

### Completed independent review and lead resolution

Exactly one reviewer ran with shared isolation, async mode, review role, Codex `gpt-6-astra`, `reasoningEffort: high`. It completed without edits, builds, tests, commits or children. Review task: `node:delegated-task:command%3Amcp%3Aeb3aeb40-6346-42fd-88a2-abcdf2308b88%3Adelegate-task%3Aboo-5ivg-review-astra-20261113-1`. Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3Aeb3aeb40-6346-42fd-88a2-abcdf2308b88%3Adelegate-task%3Aboo-5ivg-review-astra-20261113-1>.

Original verdicts at reviewed HEAD `e1928da487dfc963b7aab70ff9bec335c62f7d7d`, against base `e72d2335b1197080464e2381b923b9b310429da2`:

| Assessment | Original verdict | Reviewer evidence | Findings | Validation gaps |
| --- | --- | --- | --- | --- |
| Correctness | pass | Traced production source, real-record tests and their guard control; inspected preserved facts and saved passing logs | No runtime regression; one low-severity provenance correction below | Tests inspected, not rerun |
| Ticket fulfillment | pass | Every production entry reaches worker execution; decode and text copies finish there; inspected installed Dart SDK's awaited computation and `Isolate.exit` return | No unmet material requirement | Guard observes record opening; source trace establishes decode/copy location. This combination meets the ticket at the reviewed head, but the guard alone does not detect every possible future relocation of decode |
| Design | pass | Existing owners retain loading, pending writes, download holds, decode and speech-worker state; the test guard adds no production interface | No substantiated ownership, information-leakage or change-amplification defect | Static assessment; no performance measurement required or performed |

Design sources cited by the reviewer: User's reuse of the existing owner, Ousterhout's information hiding, and Muratori's rule against unnecessary machinery. Overall original verdict: pass, no blocking findings or unverified material requirements.

Finding R1 (low, documentation only): following the speech-reader history from the former line 50 led to `8e659ae5`, which introduced held preparation, rather than the commit that removed speech-record persistence. Remedy: split the attribution and cite `5944606e` for the speech change. Lead resolution: inspected `git show 5944606e5fa5b76a019f870a491ba322bc80100e -- lib/reader/platform_io.dart lib/reader/mobi.dart`, confirmed both renamed helpers and the removed `AdmittedBooks.keep` calls, and corrected the provenance above. No behavior changed, so no new red/fix cycle or test run was warranted. This is the lead's resolution, not a second review or a claim of reapproval.

The reviewer also noted that raw logs alone do not establish shell exit codes or every invocation setting. The lead observed exit 0 for each recorded command; the ticket preserves their exact invocations. Missing iOS SDK messages, expected SQLite failure-path diagnostics and optional skips remain explicit limitations. The original tests and production source are unchanged after review. All lead commands and the reviewer have finished; no findings or forks remain unresolved. Parent integration, acceptance, hardening and ticket closure remain outstanding.

## Parent integration and closure — 2026-11-13

Integrated the two child commits as b7ecd449 and a6669f87 on main. The only conflict was the ticket: preserved the parent launch record and the child's corrected survey claim and full evidence. Inspected the entire original-base diff, completed reviewer assessment and saved final logs. All three review assessments pass; the documentation finding was corrected by the lead. No production code changed.

Parent verification ran sequentially through `nix develop --command bash -c` with `set -e`; the driver exited 0. Exact inner commands:

- `dart format --output=none --set-exit-if-changed lib/reader/admitted_books.dart lib/reader/epub/publication.dart lib/reader/platform_io.dart lib/reader/mobi.dart test/reader/admitted_books_test.dart`: 5 files, zero changes; `/tmp/boo-5ivg-integrated-format.log`.
- `flutter analyze --no-pub lib/reader/admitted_books.dart lib/reader/epub/publication.dart lib/reader/platform_io.dart lib/reader/mobi.dart test/reader/admitted_books_test.dart`: no issues; `/tmp/boo-5ivg-integrated-analysis.log`.
- `flutter test --no-pub --concurrency=2 --reporter=expanded test/reader/admitted_books_test.dart test/reader/publication_test.dart test/reader/mobi_document_test.dart test/reader/unknown_format_test.dart test/reader/book_words_reader_test.dart test/reader/text_outline_test.dart test/reader/downloaded_reader_test.dart test/reader/session_native_test.dart test/downloads test/speech test/crossings/speech_landings_test.dart`: 453 passed, no failures or skips; `/tmp/boo-5ivg-integrated-affected.log`.
- `git diff --check d5251da58ede970a2d8522b4ee8f10ec657bd90f HEAD`: passed.
- `git diff --exit-code d236137d8640dd289d35d6262e0be68e5248a3f2 HEAD -- lib test/reader/admitted_books_test.dart`: empty, exit 0. Integrated production and the changed tests are identical to the child-tested versions.

The child's full suite (3,497 passed, 27 skips) remains child evidence; parent did not repeat it because only ticket text differs and the affected checks pass. Boundary instrumentation proves record-opening placement; source tracing establishes decode and copy placement. No Android performance, device acceptance, coverage or mutation claim. Closed after integration and verification; release acceptance and hardening remain separate.
