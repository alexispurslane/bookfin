---
id: boo-lj72
status: in_progress
deps: [tb-9mcf]
links: []
created: 2026-11-10T21:56:07Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Remember each book’s PDF view and margin trimming

User changed the product decision on 2026-11-10: remember each book’s last Original/Page words/Text choice and Trim margins on/off across app restarts. Supersedes session-only view in tb-9mcf and account-wide trim behavior. Use account-scoped book identity, one saved preference owner and existing durable reading settings storage. Restore before first useful reader view; preserve legacy settings sensibly and never lose positions, history or bookmarks. Keep font size behavior unchanged. Include restart, book/account isolation, failed-save/retry, legacy migration and UI restoration behavior evidence. Update the plan to the new settled decision.

## Acceptance Criteria

Reopening each of two books after restart restores its own exact PDF view and trim choice. Switching accounts cannot leak preferences. Changes persist through the real reading store without rewriting or losing reading records. Required checks and one fresh review with resolved findings.


## Notes

**2026-11-10T21:58:23Z**

Launched Sol xhigh lead from c9200c0; taskId node:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-20261110-boo-lj72-per-book-1; childThreadId thread:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-20261110-boo-lj72-per-book-1; clientRequestId sol-xhigh-20261110-boo-lj72-per-book-1. Lead builds, exactly one fresh Sol xhigh reviewer, lead fixes. No devices/hardening.

**2026-11-10T22:22:07Z**

Build stage complete in t3/remember-pdf-view-settings from c9200c085612a0978dd56d4fa1ac943c1f92a67d. ReaderSession now owns per-account Book.id PDF choices in existing reading settings and derives the current choices without duplicate session fields. Legacy global trim remains only the untouched-book fallback. No font-size or record model changes. Both real LocalResumeStore transports were traced; arbitrary settings metadata already survives, so no storage changes were needed. Meaningful red: session-red.log shows book/account leakage, failed restart and first-frame restoration, ignored malformed preferences; an unrelated empty-record test fixture was corrected. store-red.log shows seven intended failures across preferences and actual SQLite reopen/retry. Green: 78 focused tests passed in focused-final.log, including both storage backends, all three exact views, book/edition/account isolation, legacy SQLite migration, malformed durable settings, failed SQLite save/retry and retained reader behavior. Logs: /tmp/bookfin-boo-lj72. Required format/analyze/full suite and one fresh read-only review remain. Existing preferences-only invariant-check limitation recorded separately as tc-eri9; SQLite invariant checks pass. No devices, coverage, mutations, native changes, push, merge, PR or closure.

**2026-11-10T22:31:12Z**

Required checks passed after correcting three new analysis lints: dart format --output=none --set-exit-if-changed lib test integration_test tool: 403 files, 0 changed, exit 0 (/tmp/bookfin-boo-lj72/format-final.log); flutter analyze --no-pub lib test integration_test: no issues, exit 0 (/tmp/bookfin-boo-lj72/analyze-final.log); flutter test --no-pub --concurrency=2 --reporter expanded: 2644 passed, 21 skipped, 0 failed in 4m35s, exit 0 (/tmp/bookfin-boo-lj72/full-final.log). The initial unscoped root analysis also included existing standalone tool/research errors; its 84-issue output is preserved as analyze-root-initial.log, not mistaken for the required application analysis. iOS SDK warnings are host limitations and did not fail tests. The one authorized fresh codex/gpt-6.1-sol xhigh read-only reviewer is running with clientRequestId boo-lj72-review-d5e3fbf-20261110-1 against original base through d5e3fbfb27c9b15f547ecc03e6db8743f93c51d5. No second reviewer is permitted. Ticket remains in_progress until parent integration.

**2026-11-10T22:53:35Z**

The one authorized fresh read-only review completed against c9200c085612a0978dd56d4fa1ac943c1f92a67d..d5e3fbfb27c9b15f547ecc03e6db8743f93c51d5 and observed the lint fixes through b5d8057e464f84f6de70f43fc2d0d880d85f0331. Preserve its ORIGINAL verdicts: correctness FAIL (F1), ticket fulfillment UNVERIFIED pending F1, software design PASS. F1 is P2: the new growing pdfBooks metadata made ordinary saves synchronously copy and JSON-encode all book choices on the UI isolate. The reviewer found no record loss or separate ownership/design defect. Review gaps: static analysis only, no frame-delay measurements or device proof; the completed scoped application analysis is not a clean whole-root analysis of the unrelated tool/research sources. No second review was started or is permitted.

Lead resolution of F1: ReaderSession now keeps one validated serialized settings snapshot and replaces it only on an explicit choice change; ordinary position saves reuse the snapshot without reconstructing each book entry. LocalResumeStore uses its existing worker mechanism for growing settings copies and metadata encoding, including audio saves retaining reading metadata. SQLite accepts already encoded metadata while keeping journal changes incremental; it does not send all retained history to a worker per save. The preferences backend derives and encodes the whole account in a worker where isolates exist. Existing ordered writes enqueue before asynchronous settings preparation finishes, preserve account ownership and caller snapshots, and observe preparation errors even while an earlier write waits. Cached views, settings-only SQLite restore and recovery fast paths now include metadata size, not just record counts, when choosing worker execution. Bounded short scalar settings retain the existing inline fast path. The web still has no worker isolates.

Meaningful red: /tmp/bookfin-boo-lj72/F1-red.log has four failures: both durable backends invoke a JSON guard on the UI isolate, audio metadata lacks worker-produced text, and settings copies bypass workers. /tmp/bookfin-boo-lj72/F1-read-red.log separately proves settings-only SQLite restart restores large metadata inline. Green: five new tests use real isolates and 2,000 book entries, verify exact worker-produced durable text, actual fresh-store reads, audio preservation, reverse-submission-order worker completions across Alice/Bob, immutable caller snapshots and settings-only cached reads. /tmp/bookfin-boo-lj72/F1-focused-final.log: 57 tests pass, including durable PDF preferences, failed SQL save/retry, first-frame restoration and existing incremental-save/worker behavior. Two legacy preferences migration tests now account for the necessary additional worker encoding hop instead of the former inline encode. Required post-fix format: 404 files, zero changed (/tmp/bookfin-boo-lj72/F1-format-final.log). Required post-fix scoped analysis: no issues (/tmp/bookfin-boo-lj72/F1-analyze-final.log). Full suite is running; its result will be recorded separately. No product fork is open. Ticket remains in_progress for parent integration.

**2026-11-10T22:57:45Z**

Post-F1 final verification complete: flutter test --no-pub --concurrency=2 --reporter expanded passed 2649 tests with 21 skipped, zero failures, in 4m07s; exit 0, /tmp/bookfin-boo-lj72/F1-full-final.log. Combined with F1-focused-final.log (57 passed), F1-format-final.log (404 files, zero changed), F1-analyze-final.log (scoped lib/test/integration_test, no issues), and clean git diff --check, F1 is resolved by lead verification. The original reviewer verdicts remain fail/unverified/pass; no re-review was requested or claimed. The implementation and F1 fix are ready for parent integration, not installed or merged. No devices, coverage, mutation, native OCR, push, merge, PR, or ticket closure were performed. The unrelated preferences invariant-check follow-up tc-eri9 remains open, and boo-lj72 remains in_progress until the parent merges.
