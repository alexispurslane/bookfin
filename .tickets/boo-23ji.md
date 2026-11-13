---
id: boo-23ji
status: closed
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

**2026-11-13T09:04:22Z**

Original sole review, preserved before direct fixes. Reviewer task node:delegated-task:command%3Amcp%3A00ccb81b-948b-449b-b63e-b380dbe5be5e%3Adelegate-task%3Aboo-23ji-sole-review-astra-high-20261113; clientRequestId boo-23ji-sole-review-astra-high-20261113. Provider codex, model gpt-6-astra, reasoningEffort high, shared checkout, async, read-only. Completed 2026-11-13T09:00:50Z. No second review is authorized or claimed.

Full original report: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A00ccb81b-948b-449b-b63e-b380dbe5be5e%3Adelegate-task%3Aboo-23ji-sole-review-astra-high-20261113>.

Reviewed original base 7704c364011c83e52aabc43e6d9d74011db2d162 through 3fb3ae1423650a16b0b2662977335501a8350e98. Original verdicts: correctness changes_required; fulfillment changes_required; software design changes_required; overall changes_required. Each assessment cited the same finding, R1. These verdicts are not replaced with approval after the fix.

R1, medium severity, originally static reasoning rather than execution: a document finishes opening after closeView, account replacement, or another open invalidates its request; its disposal throws. session.dart:893-894 directly awaited admitted.dispose. The enclosing catch at line 1007 discarded that failure because _live(generation) was false. Expected: release and report the original failure and stack regardless of request lifetime. The normal _clear path already queued and reported release at line 777. Remedy: one session-owned document-release operation used by both callers. Design sources: User, one owner operation per semantic transition; Ousterhout, aggregate failure handling. ReaderSession receives both current and late documents. Maintaining two disposal/reporting paths already caused this missed caller and would require parallel edits for future reporting changes.

Original supporting review evidence: pdf.dart:1111 attempted every release stage; pending-work drainage at 911/1125; once-only disposal and owner removal at 1109/1128; first-error/stack preservation at 1115; failed survey state and no retries at book_survey.dart:289/359; recognition-worker release after owned-read failure at ocr.dart:609; later current-document opens at session.dart:777/865; existing SerialQueue reused without new lifecycle framework. Tests cited pdf_close_test.dart:139,179,237,262,288 and ocr_read_lifetime_test.dart:128. Reviewer inspected the saved red/green logs, 68 focused passes, 1788 affected passes/21 skips, 3405 full passes/27 skips, clean analysis/format output and empty diff-check output. Those were builder-produced logs, not independent reviewer executions; command flags and exit codes were builder-reported metadata.

Original gaps: no late-disposal regression (addressed below); native disposal faults occur after actual native release and do not prove recovery from a native crash or failure before release; the delayed final-survey-save plus analysis-failure combination was supported by static inspection without a directly gated test; independent execution, devices/browser, coverage and mutation testing were prohibited; optional corpus/benchmark/external-book/proof-runner skips remain unverified; host iOS SDKs are absent.

Direct R1 fix: tests hold document admission, invalidate the request by closing, changing accounts, or opening another book, then fail the late document's disposal after real native release. All three tests failed on the reviewed implementation with an empty report list (r1-red.log, exit 1). ReaderSession._releaseDocument now owns both queueing and reporting; _clear and rejected late admission both call it. All three pass (r1-green.log, exit 0), checking one native release, one report with the identical error and stack, no alteration of the current document, and a later successful open/close. Exact red and green command: nix develop --command flutter test --concurrency=2 --reporter expanded test/reader/pdf_close_test.dart --name 'a late document reports'. Broader post-fix checks follow; no reviewer reapproval is claimed.

**2026-11-13T09:14:07Z**

R1 resolution verified; ready for parent integration. No further production or test changes followed these checks. All commands completed, one heavy command at a time, with Flutter concurrency=2. No runs were interrupted. The only post-review failed run was the deliberate three-case R1 reproduction documented above.

Post-fix checks (logs under /tmp/bookfin-boo-23ji-logs):

- `nix develop --command flutter test --concurrency=2 --reporter expanded test/reader/pdf_close_test.dart test/reader/pdf_document_test.dart test/reader/book_survey_test.dart test/reader/ocr_read_lifetime_test.dart test/reader/pdf_session_test.dart test/reader/survey_session_test.dart test/foundation/serial_queue_test.dart` — exit 0, 71 passed (r1-focused.log).
- `nix develop --command flutter test --concurrency=2 --reporter expanded test/reader test/crossings test/speech` — exit 0, 1,792 passed, 21 skipped (r1-affected.log).
- `nix develop --command flutter test --concurrency=2 --reporter expanded` — exit 0, 3,408 passed, 27 skipped, zero failures (r1-full-flutter.log).
- `nix develop --command dart analyze lib/reader/pdf.dart lib/reader/book_survey.dart lib/reader/ocr.dart lib/reader/session.dart test/reader/pdf_close_test.dart test/reader/ocr_read_lifetime_test.dart` — exit 0, no issues (r1-analysis.log).
- `nix develop --command dart format --output=none --set-exit-if-changed lib/reader/pdf.dart lib/reader/book_survey.dart lib/reader/ocr.dart lib/reader/session.dart test/reader/pdf_close_test.dart test/reader/ocr_read_lifetime_test.dart` — exit 0, 6 files unchanged (r1-format-check.log). The preceding formatting write is r1-format.log.
- `git diff 7704c364011c83e52aabc43e6d9d74011db2d162 --check` — exit 0 (r1-diff-check.log).

R1 is resolved by the lead, with red-green evidence and final suite results, not by a second review. Both session disposal callers now use _releaseDocument (session.dart:775 and :895; operation at :797). The three controlled admission regressions start at pdf_close_test.dart:368. Original correctness, fulfillment and design verdicts remain changes_required in the preserved review record, with this resolution attached. No forks remain. Optional-test skips, native-crash limits, the statically checked delayed-save combination, and lack of device/coverage/mutation proof remain as recorded in the review. The parent owns integration, acceptance, hardening and closure; this ticket remains in_progress.

## Handoff recovery and parent integration — 2026-11-13

The first final handoff failed with the provider's Subscription Sharing usage-limit error. Inspection found clean committed work at 4417b7b4345d48547b7c487611818bc23664a191, complete passing verification and the recorded R1 resolution. No test command was interrupted. After the user said Continue, parent resumed the same child with clientRequestId `bookfin-boo-23ji-final-report-recovery-20261113-1`; recovery task `node:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Athread-send%3Abookfin-boo-23ji-final-report-recovery-20261113-1`. It returned ready_for_integration, clean, no forks, all commands/reviewer finished. No provider switch, new reviewer, production edit or passing-check rerun was used for handoff recovery.

Parent inspected the full original-base diff, all changed tests, source callers, completed original review and saved final logs. Integrated 3fb3ae14 and 4417b7b4 as d9d5c4c2 and 929ac3fd. Only the ticket conflicted; kept parent launch notes and all child evidence. Original review verdicts remain changes_required with the lead's verified R1 resolution attached. The native-crash and delayed-final-save combination limits remain as documented.

`git diff --exit-code 4417b7b4 HEAD -- lib/reader/pdf.dart lib/reader/book_survey.dart lib/reader/ocr.dart lib/reader/session.dart test/reader/pdf_close_test.dart test/reader/ocr_read_lifetime_test.dart` was empty. Parent formatting through Nix: `dart format --output=none --set-exit-if-changed lib/reader/pdf.dart lib/reader/book_survey.dart lib/reader/ocr.dart lib/reader/session.dart test/reader/pdf_close_test.dart test/reader/ocr_read_lifetime_test.dart`: six files, zero changes; `/tmp/boo-23ji-integrated-format.log`.

Parent combined verification after both integrations, run sequentially through `nix develop --command bash -c` with `set -e` (driver exit 0; `/tmp/boo-23ji-hd47-integrated-driver.log`):

- `flutter analyze --no-pub lib/reader lib/crossings lib/speech test/reader test/crossings test/speech`: no issues; `/tmp/boo-23ji-hd47-integrated-analysis.log`.
- `flutter test --no-pub --concurrency=2 --reporter=expanded test/reader/pdf_close_test.dart test/reader/pdf_document_test.dart test/reader/book_survey_test.dart test/reader/ocr_read_lifetime_test.dart test/reader/pdf_session_test.dart test/reader/survey_session_test.dart test/foundation/serial_queue_test.dart`: 71 passed, no skips or failures; `/tmp/boo-23ji-integrated-focused.log`.
- `flutter test --no-pub --concurrency=2 --reporter=expanded`: 3,518 passed, 27 existing optional/external-fixture skips, zero failures, 4:44; `/tmp/boo-23ji-hd47-integrated-full.log`.
- `git diff --check c4c3959f HEAD`: passed after both integrations.

No production or test edits followed these checks. Only ticket records and next-ticket launch records changed. All parent commands finished. The existing t5-rplx intermittent unread-record failure remains unexplained; this passing run does not close it. No device/browser, Android latency, coverage or mutation claim. Closed after integration and combined host verification; release acceptance and hardening remain separate.
