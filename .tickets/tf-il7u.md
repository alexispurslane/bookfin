---
id: tf-il7u
status: in_progress
deps: []
links: []
created: 2026-11-13T13:23:39Z
type: bug
priority: 3
assignee: Alexis Purslane
---
# Investigate the intermittent idle-layout frame test failure

During boo-hjal verification, test/reader/epub/page_source_frames_test.dart:188 failed: idle layout gives way to each frame that is scheduled, and goes on once no frame is scheduled. Expected far() false, got true, with reason idle steps ran in a row between frames. The same test passed in the preceding reader/crossings suite. Logs: tool/evidence/boo-hjal/08-reader-crossings.txt and 12-full.txt. The test and scheduler implementation were unchanged by boo-hjal. Cause is not established; investigate whether the prepared source can finish idle work before Redraws schedules its first frame.

## Acceptance Criteria

Reproduce the cause with controlled scheduling. Preserve the production scheduling contract. Use a deterministic readiness or work-count assertion, not a larger delay or timing threshold. Run the unchanged relevant behavior and full suite.


## Notes

**2026-11-13T13:25:55Z**

The unchanged targeted frame suite passed all five tests immediately after the full run: tool/evidence/boo-hjal/13-frames-repeat.txt. No production scheduling change or test timing adjustment was made. A full-suite rerun is next.

**2026-11-13T13:31:26Z**

The second unchanged full run passed 3,535 tests with 27 skips: tool/evidence/boo-hjal/14-full-repeat.txt. The earlier intermittent failure remains unresolved as a follow-up; no frame test or scheduling implementation was changed.

## New recurrence and parent scope — 2026-11-13

boo-hwoz reproduced the same assertion in a full suite (3,673 passed,
27 skipped, one failure), in an unchanged five-test frame suite (four passed,
one failure), and with its sole changed production file temporarily restored
to the original base (same four passes and one failure). Logs:
`/tmp/bookfin-boo-hwoz/full-suite.log`, `frames-repeat.log`, and
`frames-original-production.log`. The original reviewer retained the failure
and no root-cause claim. Parent verified the command-log hashes and full-run
completion. These results show the failure can occur without the collection
query change; they do not diagnose it. The previously passing parent suites
remain separate evidence, not a resolution.

Current test open() prepares a PageSource through tester.runAsync. The failing
test starts a deep page request before mounting Redraws, whose post-frame
callback requests another frame. PageSource.scheduleBetweenFrames gates idle
work on hasScheduledFrame and framesEnabled; urgent work follows a different
rule. The ordering observation is a hypothesis, not a settled cause.

Investigate and fix this ticket directly, preserving the documented contract:
idle layout yields while a frame is scheduled or the app is backgrounded,
urgent layout can progress during animation, and idle work resumes when its
hold ends without a busy event-loop poll. Establish exactly when a frame is
pending, when preparation/page work is admitted, and when idle steps execute.
Use controlled scheduler/worker readiness and observed step or frame counts
rather than host speed, larger sleeps, extra paragraphs or looser thresholds.
A deterministic test must fail if idle work is deliberately allowed through
the protected interval; a passing rerun alone is insufficient cause evidence.
Do not weaken valid runtime behavior to satisfy an invalid test setup. If the
fault is only test ordering, preserve production and demonstrate both the old
race and the corrected test's ability to detect the intended contract break.
If a production defect is reproduced, write the failing behavior test before
fixing its existing owner. Start no generic scheduler or testing framework.

Own test/reader/epub/page_source_frames_test.dart and only narrow scheduler/
fixture changes proven necessary. Check related animation/background cases,
not just the one failure. Preserve settings, eviction, excerpt and urgent
request behavior. Run focused frame/scheduler tests and a bounded documented
repeat justified by the intermittent bug, affected reader/EPUB suites, full
Flutter tests, changed-file formatting, affected analysis and complete
original-base diff checks through Nix. Flutter concurrency at most two; one
heavy command per owner. Retain every failed/interrupted run and distinguish
cause proof, regression proof and repeat-run evidence. Exactly one fresh
Astra high read-only reviewer after Astra xhigh build, direct fixes, no second
review. No devices/browser, broad coverage or mutation campaign, timing
threshold changes, push/PR/deploy or closure. A controlled negative test of
the scheduler contract is within this bug investigation, not acceptance
hardening. Parent integrates and closes. Stop dependent work at a real
product/scheduling-policy fork rather than silently changing the contract.

## Launch — 2026-11-13

Astra xhigh lead launched from 403b803d24b5e20a9a249ca094dff477fba90eac. Running, stage uncertain; branch not reported. Exactly one fresh read-only Astra high reviewer authorized. Parent integrates and closes.

- clientRequestId: bookfin-tf-il7u-astra-20261113-1
- taskId: node:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-tf-il7u-astra-20261113-1
- childThreadId: thread:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-tf-il7u-astra-20261113-1
- Link: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-tf-il7u-astra-20261113-1>

## Ticket lead investigation and checks — 2026-11-13

Worktree `/Users/alexispurslane/.t3/worktrees/bookfin/t3-db20027d`, branch
`t3/fix-idle-layout-frame-flake`, started clean at original base
`403b803d24b5e20a9a249ca094dff477fba90eac`. The ticket was already in progress.
No inherited collection changes were edited.

The unchanged frame suite reproduced the original assertion failure. A traced
PageSource run admitted no layout before the first frame. Instead, each later
idle callback ran before Redraws requested its next frame, with no frame
pending at execution. A controlled three-step job reproduced that order and
failed the old completion assertion. Completion can be legal; it does not
prove execution while a frame was pending. Historic logs did not trace their
callbacks, so the investigation does not reconstruct every earlier run.

Only the frame test file changes. A test observer counts real scheduler
callbacks. The corrected assertion checks at most one idle callback per frame
and none while a frame is pending or frames are disabled. Two controlled tests
cover both post-frame callback orders and release after a hold. Animation,
background and urgent behavior remains covered. Production, fixture sizes,
layout budgets and existing timing limits remain unchanged.

A single deliberate negative control removed the pending-frame guard. Five
of seven tests failed, including eleven callbacks where at most one is allowed
and a callback during the controlled hold. The original production file was
restored exactly. Five subsequent seven-test runs passed. Reader/crossing
regressions passed 1,714 tests with 21 skips; full Flutter tests passed 3,676
with 27 skips. Affected EPUB analysis found no issues. Changed-file formatting
and original-base whitespace/production-diff checks passed. All build, test, analysis and format commands use
Nix; Flutter concurrency is two, with one heavy command at a time. No command
was interrupted or stopped.

Full evidence, exact commands, original failures, diagnostic patches, hashes,
skips and limits: `tool/evidence/tf-il7u/handoff.md` and its archived logs.
One fresh Astra high read-only review follows this implementation commit.
Parent owns integration, acceptance, hardening and closure. No product fork.
Device/browser blockers t1-dth0 and t7-3j9c were not retried. t5-rplx remains
unexplained. No collection CPU work, coverage or general mutation campaign.

## Original review and final handoff — 2026-11-13

Exactly one fresh read-only Codex / gpt-6-astra / high reviewer completed.
It reviewed `403b803d24b5e20a9a249ca094dff477fba90eac` through
`e40d1abc8704800d54a6e7a54e47cfbc760b25bd`. Correctness, ticket fulfillment
and design each received pass. There were no findings, material unverified
requirements or remaining in-scope implementation work.

Reviewer: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3Ab85060a0-b641-4521-92d0-2f4bed3c3a46%3Adelegate-task%3Abookfin-tf-il7u-review-astra-high-20261113-1>

`tool/evidence/tf-il7u/review-original.json` preserves the original report.
Its gaps remain explicit: no historical callback traces; the inherited
completion helper also accepts errors; the reviewer inspected saved runs;
optional tests remain skipped; design used static and archived evidence.
The controlled release test independently proves actual callback progress.
No fix or second review was needed. Only evidence and ticket updates follow
the reviewed implementation. Parent still owns integration and closure.
