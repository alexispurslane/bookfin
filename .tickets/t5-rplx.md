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

## Ticket lead investigation — 2026-11-13

Worktree `/Users/alexispurslane/.t3/worktrees/bookfin/t3-30d0db95`, branch
`t3/unread-record-retry-race`, started clean at original base
`62f4fb238861fd601acb2668a9a4d646c8a28c77`. The initial base-to-checkout
diff was empty. The ticket was already in progress.

The investigation establishes an insufficient test observation. In a controlled
legal storage ordering, the next visible place retried the failed read, then
started a save that the test held pending. The unchanged `pumpEventQueue`
completed while that save waited. A fresh store read returned no resume.
Releasing the save produced one resume and preserved font size 22 without a
reader flush. Applying the original length assertion to the earlier snapshot
failed with `Actual: []`. The controlled completion check then passed.

The historical failures remain retained, with no claim to reconstruct their
untraced schedules. No production defect was established. Only the existing
test wrapper and test observation change: the wrapper signals completion after
the real save succeeds; the test awaits that signal, then checks the saved
place and font size in a fresh store and font size in the reader. The fixture
and other behavior tests remain intact. No timer, pump count or storage
threshold changes. Production and the integrated tf-il7u correction are
unchanged.

A bounded negative control removed only the automatic `_readAgain()` call
from the unread branch of `ReaderSession._save`. The corrected test failed
at its diagnostic five-second timeout because no save completed. Production
was restored byte for byte in `finally` and checked against the original base.
The diagnostic timeout is not part of the committed test.

Six independent Flutter processes each passed all five unread-record tests.
This bounded repetition checks stability after the controlled proof; it is
not a reliability estimate or evidence of historical scheduling. The focused
reader/store suite passed 85 tests. Reader, sync, durability and app suites
passed 2,225 tests with 24 skips. The full suite passed 3,692 tests with 27
skips. Affected analysis found no issues; changed-file format verification
changed no files. All builds, tests, analysis and formatting used Nix, with
Flutter concurrency two and one heavy command at a time.

`docs/evidence/t5-rplx-verification.json` records exact commands, results,
skips, diagnostic patches, complete log paths and hashes. Logs and diagnostic
source copies are retained in `/tmp/t5-rplx-logs/`, including copies of the
boo-o3cm and boo-zs5i failures. The preference-backed test uses mocked
SharedPreferences and real store work; it makes no physical-device crash or
OS-process restart claim. Existing focused and affected tests cover failed
writes, account changes, retained records and SQLite durability.

One fresh read-only Astra high reviewer follows this implementation commit.
No product fork. Parent owns integration, acceptance, hardening and closure.
