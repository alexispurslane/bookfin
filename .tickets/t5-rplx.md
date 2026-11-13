---
id: t5-rplx
status: in_progress
deps: []
links: []
created: 2026-11-13T03:25:09Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [testing]
---
# Investigate the intermittent unread-record recovery test failure

During boo-jld0 verification on base 8caf18ebcfcaa02df67c49767cdee11d5109f2eb, the full Flutter suite at concurrency 4 reported 3130 passed, 25 skipped and one failure in test/reader/unread_records_test.dart: the next place after a failed read opens the records again without a flush. At line 97, the saved resumes list was empty instead of containing one entry. The test waits with pumpEventQueue after accepting the visible place. Reader and record-store production code were unchanged by boo-jld0. A wait for real storage completion may be missing, but that cause is not yet established. Related completed behavior ticket: boo-y2sj.

## Acceptance Criteria

Establish whether the failure is a storage race or an insufficient test wait. Preserve the requirement that the next reading place retries storage without an explicit flush. Demonstrate a meaningful failing test for any production defect, then pass the focused tests and the full suite at concurrency at most 4.

## Notes

**2026-11-13T03:25:58Z**

The immediate isolated retry, nix develop --command flutter test --concurrency=1 test/reader/unread_records_test.dart --reporter expanded, passed all 5 tests. This confirms an intermittent failure in the full run, not its cause. No reader or record-store fix was attempted in boo-jld0.

**2026-11-13T03:38:43Z**

Two later full-suite runs at concurrency 2 passed: 3131 passed and 25 skipped before the final catalog access-recovery fix, then 3132 passed and 25 skipped after that fix and its regression test. The reader recovery test passed in both. The original concurrency-4 failure remains recorded for investigation.

## Additional observation during boo-o3cm (2026-11-13)

On base `77e6d62e3a7a6f7018fdeba3efd9d8862278aa81` with boo-o3cm download-binding changes, `nix develop --command flutter test --concurrency=2` finished with 3374 passed, 27 skipped and one failure: the same test and line 97, an empty saved `resumes` list instead of one entry. Log: `/tmp/boo-o3cm-full.log`. `nix develop --command flutter test --concurrency=2 test/reader/unread_records_test.dart` immediately passed all 5 tests unchanged; log: `/tmp/boo-o3cm-unread-retry.log`.

Inspection confirms that this test uses `LocalFiles` from `test/playback/playback_test.dart`, not `LocalDownloads`, and constructs ReaderSession directly without AccountBinding. The reader, record store, test file and its `pumpEventQueue` wait are unchanged by boo-o3cm. The affected suite, including all reader tests, passed three times before this full-suite failure. No cause is claimed from this evidence, and no timing threshold, test wait, or reader behavior was changed. Investigation remains owned by this ticket.

The complete unchanged retry, `nix develop --command flutter test --concurrency=2`, passed 3375 tests with 27 skips; log `/tmp/boo-o3cm-full-retry.log`. The recovery test passed in that run. This confirms another intermittent occurrence, not its cause; the ticket remains open.

## Investigation scope — 2026-11-13

Establish a production defect versus an insufficient observation of storage
completion. Control storage readiness and completion rather than adding sleeps,
larger pump counts or looser timing thresholds. The next visible place must
retry storage without an explicit flush. Keep production unchanged if the test
observation is the only defect. Prove that the corrected test catches a
deliberately broken retry contract, restoring the negative control afterwards.

Preserve earlier font size and records, failed writes and account isolation.
Retain historical failures, controlled cause evidence and justified bounded
repeat results. Later green suites alone do not identify the cause. Run focused,
affected and full suites through Nix at concurrency at most two, plus analysis,
formatting and complete-diff whitespace checks. This tighter concurrency limit
supersedes the original limit of four. Exactly one fresh read-only reviewer
assesses the complete change. Parent owns integration, acceptance, hardening
and closure. No device/browser work or general mutation campaign is in scope.

## Parent launch record — 2026-11-13

- Original base: `62f4fb238861fd601acb2668a9a4d646c8a28c77`.
- Task ID: `node:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-t5-rplx-astra-20261113-1`.
- Child thread ID: `thread:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-t5-rplx-astra-20261113-1`.
- Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-t5-rplx-astra-20261113-1>.
- Client request ID: `bookfin-t5-rplx-astra-20261113-1`.
- Branch at launch inspection: `t3/unread-record-retry-race`.
- Worktree: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-30d0db95`.
- Lead: codex/gpt-6-astra, xhigh. One fresh read-only reviewer: the same model, high.
- Stages: build, review, then one fix stage if needed. Parent handles integration and closure.
- Launch accepted and running. No implementation result or acceptance is claimed.
