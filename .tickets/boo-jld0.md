---
id: boo-jld0
status: closed
deps: []
links: []
created: 2026-11-12T23:41:00Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Refresh the catalog on resume only when it is stale, and skip the write when nothing changed

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/main.dart:331 starts a full catalog refresh at every return from hidden. lib/catalog/controller.dart:647-683 downloads every page of every library, builds the catalog and writes it, also when the content digest did not change. The code records `completedAt` and never reads it. test/app/resume_refresh_test.dart locks in one refresh for each return. Let the catalog own the freshness decision: refresh on resume after an unreachable result, or when the last success is older than a set interval, and skip the build and the write when the digest is unchanged. The interval is a tradeoff that the user sees, so the user decides it.


## Notes

**2026-11-13T01:09:38Z**

User decision, 2026-11-12: a return to the foreground refreshes the catalog only when the last successful refresh is older than 1 hour. Launch, a refresh by hand, and a return after an unreachable result refresh as before. Skip the build and the write when the content digest is unchanged. test/app/resume_refresh_test.dart changes with this ticket.

**2026-11-13T03:10:37Z**

Astra ticket lead started from 8caf18ebcfcaa02df67c49767cdee11d5109f2eb. Task node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-jld0-astra-20261112-1; child thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-jld0-astra-20261112-1; clientRequestId bookfin-boo-jld0-astra-20261112-1. Builder uses codex/gpt-6-astra reasoningEffort xhigh; fresh reviewer uses the same model at high. User-approved one-hour freshness rule and unchanged-content write avoidance only. Verification and integration pending.
## Implementation notes

The catalog owns the one-hour decision through `resume()`. The app reports a return from hidden. Launch and manual refresh still use the unconditional refresh. A return after an unreachable result also retries. A running sign-in, restore or refresh continues without another request.

The controller keeps the latest successful refresh time for the current account session. Before that, it reads the saved snapshot's `completedAt`. Unchanged successes update the session time without changing the saved snapshot. Corrections preserve that time. Account changes clear it. Failed, incomplete, cancelled and superseded operations do not advance it. Launch still refreshes after showing saved books, so this needs no new persistent metadata or storage migration.

The worker validates pages and calculates the existing digest before it builds books. The digest covers entries and corrections. Matching content reuses the books. When the library names, hidden libraries, access state and saved snapshot also match, it returns without encoding or writing the catalog. Changed account metadata still saves through the existing store, even with unchanged books.

Every catalog write records whether storage still holds the active snapshot. A cancelled or superseded operation can finish its disk write. A later refresh repairs that saved snapshot even when the incoming books match the visible ones. Reads wait for earlier writes. Failed writes also require the next refresh to save. Refreshes and corrections retain the existing serialized write order.

A successful refresh always ends the current access denial. This also applies when preparing the denial for storage failed, so the saved snapshot never recorded it. An unchanged response can then restore access without a catalog write.

## Verification

- Red: the first focused run reported 75 passed and 8 failed. Failures exposed unconditional resume requests, repeated book builds and writes, and unsuccessful unchanged refreshes when writes fail. The restored-cache fixture was then corrected to use the same normalized entries as a real refresh.
- Red for interrupted writes: 10 passed and 2 failed. Restart showed a cancelled book title or a superseded hidden-library choice. Both pass after the storage-state fix.
- Red for access recovery: the new denial-preparation failure test reported access revoked after a successful unchanged response. It passes after ending the denial on every successful refresh.
- Final focused check: `nix develop --command flutter test --concurrency=4 test/catalog test/app/resume_refresh_test.dart --reporter expanded` passed all 361 tests.
- Affected analysis: `nix develop --command flutter analyze lib/catalog/controller.dart lib/catalog/store.dart lib/main.dart test/catalog/controller_test.dart test/catalog/catalog_signals_test.dart test/app/resume_refresh_test.dart` reported no issues in 3.1 seconds.
- First full Flutter suite: `nix develop --command flutter test --concurrency=4 --reporter expanded` finished with 3130 passed, 25 skipped and 1 failure. The unchanged reader test `the next place after a failed read opens the records again without a flush` found an empty saved resume list. All 5 tests in that file passed in the isolated retry: `nix develop --command flutter test --concurrency=1 test/reader/unread_records_test.dart --reporter expanded`. New ticket `t5-rplx` records the intermittent failure without assuming its cause.
- Full-suite retry before the final access-recovery fix: `nix develop --command flutter test --concurrency=2 --reporter expanded` passed 3131 tests and skipped 25 in 5 minutes 28 seconds.
- Final full suite after the access-recovery fix: `nix develop --command flutter test --concurrency=2 --reporter expanded` passed 3132 tests and skipped 25 in 5 minutes 39 seconds.

## Review

The fresh Codex `gpt-6-astra` reviewer at high reasoning effort reviewed the complete base `8caf18ebcfcaa02df67c49767cdee11d5109f2eb` to implementation `18a4ca94d01d45ad09095c6a8b5453df9035fc1d` diff. Correctness: pass. Fulfillment: pass. Design: pass. No material findings or unresolved forks.

The reviewer inspected the source, required guidance, focused checks, analysis, final full-suite log and the interrupted-write and access-recovery failures. The review used static inspection and existing logs only. It ran no tests or builds and changed no files. The initial red-run and isolated reader-retry results remained builder-reported evidence. This final ticket update changes no reviewed code.

Review thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A85497df4-78bb-4d05-a8b5-6654de08598d%3Adelegate-task%3Aboo-jld0-review-astra-20261113-1>

No personal-record sync, reader session, PDF or storage migration changes. Coverage and mutation testing remain with the parent after user acceptance. Integration and ticket closure remain with the parent.


## Integrated verification, 2026-11-12

Integrated on main through f84593f6. The parent ran the combined full Flutter suite through the project Nix dev shell: `flutter test --no-pub --concurrency=4 --reporter expanded`. Result: 3,196 passed, 25 skipped, zero failures, 2 minutes 30 seconds. Log: /tmp/bookfin-astra-integrated-final.log. Affected analysis found no issues: /tmp/bookfin-astra-integrated-analysis.log. The command exited successfully and git diff --check passed.

This verifies the combined PDF visibility/History corrections, sync transport and writer registration, and catalog freshness changes. Existing external plugin fixtures and opt-in conditions remain skipped; this is not live plugin or Android acceptance. Coverage and mutation testing remain with the orchestrator after user acceptance. The parent closes this ticket after integration and the successful combined suite.
