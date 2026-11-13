---
id: boo-23ji
status: in_progress
deps: []
links: [boo-x1zf]
created: 2026-11-12T23:41:01Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Release PDFium and keep the close chain alive when a PDF close fails

## Settled integration scope — 2026-11-13

Keep the existing document, survey and session owners. Make cleanup release all owned resources even when awaited work or survey shutdown fails. Preserve the original failure for the appropriate caller; do not treat a failed contract as successful work or retry a failed survey page indefinitely. A failed previous close must not poison the session's later open/close chain. Include pending PDF work, text-supply shutdown, PDFium disposal, and owner release in the lifetime audit; no new lifecycle framework or navigation redesign.

Prove meaningful failures with controlled completion/failure tests, including a non-Exception Error, once-only disposal, later successful open/close, and survey failure retention. Inspect existing contract semantics explicitly. Required checks: focused regressions, reader/crossings/speech affected suites, full Flutter suite, changed-file analysis/format and diff checks. Nix, concurrency two, one heavy command at a time. No devices, coverage, mutation testing, push or PR. One fresh read-only Astra high reviewer; direct Astra xhigh fixes with red-green evidence. Parent integrates and closes.

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: path confirmed, trigger plausible (it needs an Error that is not an Exception). lib/reader/pdf.dart:1108-1118, lib/reader/session.dart:663-669, lib/reader/book_survey.dart:279-338. `_dispose` awaits `survey.close()` before its `try`, so an Error from the survey skips `_document.dispose()` and leaks the PDFium handle. The `_closing` chain of the session handles only Exception, so it stays failed: every later open reports "could not be opened" and every later document leaks. The survey does not add the failing page to `_failed`, so each page turn runs the failing analysis again. Put the release in a `finally`, keep the chain going after any failed close, and mark the page failed before the Error propagates.

## Launch — 2026-11-13

Astra xhigh ticket lead launched from 7704c364011c83e52aabc43e6d9d74011db2d162. Status running, stage uncertain. Exactly one Astra high read-only reviewer authorized.

- clientRequestId: bookfin-boo-23ji-astra-20261113-1
- taskId: node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-23ji-astra-20261113-1
- childThreadId: thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-23ji-astra-20261113-1
- Link: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-23ji-astra-20261113-1>

## Notes

**2026-11-13T08:44:39Z**

Implementation evidence, 2026-11-13 (integration and closure remain with the parent).

The clean starting branch was t3/pdfium-close-cleanup at 7704c364011c83e52aabc43e6d9d74011db2d162. Existing owners remain: PdfBook owns its survey and text supply; PdfRuntime owns native documents; ReaderSession orders document closes. Native close now attempts cancellation, drains pending work and the survey, closes the text supply, disposes PDFium, and releases the runtime owner exactly once. The first failure and stack remain the disposal result. BundledEnglishText also releases its recognition-worker hold after an owned download read fails to release.

BookSurvey keeps a failed run as its result, reports it through FlutterError, and does not start it again on follow/resume. It marks a failed page before propagating an Error. StateError and AssertionError remain failures. A distinct PdfClosedError represents an ordinary request after closing begins, so expected cancellation does not mask contract failures. Survey close waits for the final save even after analysis fails. ReaderSession reports close failures without making later documents inherit them.

Tests observe real PDFium through its existing engine interface and use completion gates for pending page work, text-supply close, and download-read release. No production test hooks. The initial seven-test run failed on all seven intended behaviors (red-close.log); leaked books also caused teardown failures in that deliberately failing run. The native cleanup subset then passed 3/3 (green-native-close.log); the first complete regression run passed 7/7 (green-close.log). The additional cancellation and owned-read-release tests both failed meaningfully (red-cancel-read-release.log), then the two affected test files passed 12/12 (green-close-read-release.log). Focused integration tests passed 59/59 (focused.log).

All logs are saved in /tmp/bookfin-boo-23ji-logs. Commands use nix develop and Flutter concurrency=2. No test command was interrupted. Flutter emits existing unavailable iphoneos/iphonesimulator SDK diagnostics on this host, but host Flutter tests execute. No device/browser actions, coverage, mutations, push, PR, merge, closure, or worktree removal were performed. Broader checks and the one authorized read-only review are still pending at this note.

**2026-11-13T08:49:11Z**

The caller audit found an early textSupply.cancel in ReaderSession._clear, outside document disposal. The controlled cancellation-Error test failed there before cleanup began (red-session-cancel.log), with the expected teardown failure too. The session now delegates the whole close to the document, including cancellation, so cancellation failure is retained while all releases still run. The focused final run passed 68 tests (focused-final-cancel.log), including the existing SerialQueue suite. ReaderSession now reuses that existing queue, rather than retaining a separate serial-future mechanism. No new lifecycle framework was added.

Affected suites before the final session refactor: nix develop --command flutter test --concurrency=2 --reporter expanded test/reader test/crossings test/speech. Exit 0, 1,788 passed, 21 skipped (opt-in benchmarks/corpus tests and absent external trial books); affected.log. The full Flutter suite is running against the final behavior and includes those suites again.

**2026-11-13T08:55:50Z**

Completed verification before review. Every command finished. Logs: /tmp/bookfin-boo-23ji-logs/.

- `nix develop --command flutter test --concurrency=2 --reporter expanded test/reader/pdf_close_test.dart` — initial red: exit 1, 7 intended failures plus teardown errors from the reproduced leaks (red-close.log). After native fixes: the same command with `--name 'a survey Error|close drains|cleanup retains'` passed 3 tests (green-native-close.log). After survey/session fixes: the unfiltered command passed 7 tests (green-close.log).
- `nix develop --command flutter test --concurrency=2 --reporter expanded test/reader/pdf_close_test.dart test/reader/ocr_read_lifetime_test.dart --name 'closing during survey|a failed read release'` — exit 1, both intended failures (red-cancel-read-release.log). The same two files without `--name` then passed 12 tests (green-close-read-release.log).
- `nix develop --command flutter test --concurrency=2 --reporter expanded test/reader/pdf_close_test.dart --name 'a cancellation Error'` — exit 1, expected failure in ReaderSession._clear, plus its teardown error (red-session-cancel.log).
- `nix develop --command flutter test --concurrency=2 --reporter expanded test/reader/pdf_close_test.dart test/reader/pdf_document_test.dart test/reader/book_survey_test.dart test/reader/ocr_read_lifetime_test.dart test/reader/pdf_session_test.dart test/reader/survey_session_test.dart test/foundation/serial_queue_test.dart` — final focused run: exit 0, 68 passed (focused-final-cancel.log). Earlier focused runs passed 59 without the SerialQueue file (focused.log), then 67 after queue reuse and before the last cancellation regression (focused-final.log).
- `nix develop --command flutter test --concurrency=2 --reporter expanded test/reader test/crossings test/speech` — exit 0, 1,788 passed, 21 skipped (affected.log), before the last session changes; the full run below checks these suites again at final behavior.
- `nix develop --command flutter test --concurrency=2 --reporter expanded` — exit 0, 3,405 passed, 27 skipped, zero failures (full-flutter.log). Skips are opt-in benchmarks/corpus trials, absent trial books, and plugin/sync proofs that require their separate pinned-shell runners. Native host tests ran despite the SDK discovery diagnostics. Only Dart formatting and a class-comment clarification followed this run.
- `nix develop --command dart analyze lib/reader/pdf.dart lib/reader/book_survey.dart lib/reader/ocr.dart lib/reader/session.dart test/reader/pdf_close_test.dart test/reader/ocr_read_lifetime_test.dart` — exit 0, no issues (analysis-final.log; earlier analysis.log also passed).
- `nix develop --command dart format --output=none --set-exit-if-changed lib/reader/pdf.dart lib/reader/book_survey.dart lib/reader/ocr.dart lib/reader/session.dart test/reader/pdf_close_test.dart test/reader/ocr_read_lifetime_test.dart` — exit 0, 6 files unchanged (format-check.log). Formatting writes are logged in format.log, format-final.log and format-complete.log.
- `git diff --check` — exit 0 (diff-check.log).

The audit also inspected PdfRuntime's admission barrier, native work settlement, pdfrx's real disposal implementation, PdfPager.dispose, the stale-admission disposal caller, and the download-read/recognition-worker ownership boundary. Tests fault native disposal after the actual PDFium release so the injected failure does not itself leak a real native handle. No live-device claim is made. No forks remain. The one authorized Astra high review is next; integration, acceptance, hardening and ticket closure remain with the parent.
