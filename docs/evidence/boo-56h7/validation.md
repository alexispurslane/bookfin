# Play choices and retained places — boo-56h7

Original base: `62f4fb238861fd601acb2668a9a4d646c8a28c77`.
Worktree: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-fd6f0347`.
Branch: `t3/preserve-external-play`.
The checkout started clean at the original base. No prerequisite work was reimplemented.

## Behavior and ownership

Playback owns the choice for the open recording and every record change. A
refresh adopts the journal's typed current resume view without waiting for audio
commands. A refresh does not move the decoder. A requested choice has object
identity, so an answer to an older choice cannot select a replacement choice.
The account and the full recording's source revisions delimit its lifetime.

The catalog screen controller presents requested choices while the app is in
the foreground. It follows only Playback's choice signal and uses
`showGlassChoices`. Play from the book page, mini player, full player and reader
cover reaches that owner. The media service's Play callback uses external Play.
An already open edition's Listen button uses the same Play decision.

Before a local save replaces a remote resume, the same change set keeps both
places as stationary `preserve` History entries. These entries use the existing
History codec, writer, journal and durable transaction. They do not offer a
fictional Undo or count as listening in the recent-books list. A choice of the
remote place uses the normal `open` move, names the other device, and offers
Undo from the actual place where this phone was listening.

The local listening settings keep a pending choice's History id, original remote
action identity, source identity and whether presentation was requested. The
remote place itself is recovered from History. This is a pending question, not
a second resume store. An accepted choice clears the question. Repeated Play
and refresh reuse the same question and do not add another preservation pair.
Older builds retain the new History kind through their existing unknown-record
support; existing History JSON names remain unchanged.

## Evidence

`commands.json` records every executed build/test/format/analysis command, its
exit code, complete log path and interpretation. Logs are retained outside chat
under `/tmp/bookfin-boo-56h7-evidence/`. Compilation and fixture failures are
listed separately from behavioral red evidence.

The first regression used real preferences and SQLite stores. The remote
installation wrote a resume without a corresponding History entry. External
Play followed by a decoder update replaced that resume; History lacked its
40-second place. In-app Play also called the decoder before asking. Both tests
failed for those behaviors before implementation (`01-original-red.log`).
`original-red.patch` retains those initial two tests for the original base.

The targeted tests exercise both choice outcomes, cancellation, external Play,
foreground callbacks, every visible Play entry point, repeated operations,
newer/deleted resumes, account/edition/source changes, failed saves, process
abandonment and reopening, a SQLite transaction aborted after an inserted row,
History restoration, Undo, and refresh during held audio work. Retained tests
cover the existing writer, sync, durability, reading and crossing behavior.

## Limits

No device or browser was used. Host media-service and lifecycle callback tests
are not native lock-screen, notification or headset acceptance. That acceptance
remains parent-owned and blocked on `t1-dth0`. The parent owns integration,
acceptance, coverage, mutation testing and ticket closure.

No unrelated timing thresholds were changed. The earlier `t5-rplx` failure's
cause remains unexplained by this ticket. The integrated `tf-il7u` correction
was preserved. The parent's combined baseline of 3,692 passes and 27 skips at
`1bf2d597` is supplied context, not a run performed by this ticket lead.

## Checks before the independent review

- Focused and retained refresh regression run: 131 passed (`18-regression-green.log`).
- Final affected suite: 1,253 passed, 3 skipped (`22-affected-green.log`).
- Full suite: 3,745 passed, 27 skipped (`23-full-suite.log`).
- Affected analysis: no issues (`24-analysis-green.log`).
- Format verification: 11 files, no changes (`25-format-check.log`).
- Original-base-to-working-tree whitespace check: passed (`26-original-base-diff-check.log`).

All Flutter runs used the pinned Nix shell and concurrency 2, with one heavy
command at a time. The 53 new cases include the final failed-save presentation
retry, checked again in the affected and full suites. All earlier failures and
skips remain in the command manifest and full logs.

## Independent review and fixes

The one authorized reviewer returned `changes-required` for correctness,
fulfillment and design. `original-review.json` preserves its original report
unchanged. `review-resolutions.json` retains the thread link, original verdicts,
gaps and the ticket lead's resolution of each finding. There was no second
review, and the original verdicts have not been relabeled as passes.

R1 concerned a sync that replaced or deleted a question while its answer's seek
was held. Four reproductions failed on the two storage backends: the decoder
and recorded position moved from 11 seconds to the obsolete 40-second place.
The seek now checks the question at decoder confirmation. If it became stale,
the decoder returns to the prior local place before any move or resume is
published. Tests check the decoder, current position, current journal action,
History, Undo and replacement question.

R2 concerned restoration of a question that refresh had already withdrawn or
replaced. Twelve restart cases failed on preferences and SQLite. Refresh and
restart now share one validity rule. Marker replacement or withdrawal goes
through the existing writer without writing a resume. Restart uses the
journal's last local action for this phone's place, and checks the current
resume after loading the decoder. This also rejects an obsolete saved marker
when saving its withdrawal failed.

Two further pairs of behavioral failures tightened that rule: refresh must
await the marker write, and sync during a held restart load must replace the
question before presentation. All red logs remain in the command manifest.
The focused and retained command/refresh regression run passes 154 tests
(`39-review-regression-green.log`). The affected suite passes 1,275 tests with
3 skips (`40-review-affected-green.log`).

Command 32 had two overly broad test expectations: ordinary reopening after a
fully saved withdrawal may update the existing offline-report flag. The tests
now check unchanged action identity during reconciliation and pending-question
recovery, and the unchanged 11-second position during ordinary reopening. No
production change was made for those expectations. Command 36 passed 75 focused
cases but failed to load a nonexistent test path. Command 39 used the correct
paths and passed. Neither command failure is counted as behavioral red.

The first full-suite run after review fixes (`41-review-full-suite.log`) also
reported the existing `t5-rplx` failure: `test/reader/unread_records_test.dart`,
“the next place after a failed read opens the records again without a flush”,
line 97. Its saved resumes list was empty instead of having one entry. The
affected suite had passed that test. This ticket changes neither that test nor
reader production code. The observation matches the existing ticket; it does
not establish a cause. No wait, timing threshold or reader behavior was changed.
The immediate unchanged retry of all five tests in that file passed
(`42-unread-retry.log`).
The unchanged full-suite retry passed 3,767 tests with 27 skips
(`43-full-suite-retry.log`). Both complete full-run logs are retained. Neither
retry establishes the cause of `t5-rplx`.

## Final verification

The final code passes the 154-test focused regression run, the 1,275-test
affected run (3 skips), and the 3,767-test full retry (27 skips). The original
full failure remains reported above. Final affected analysis reports no issues
(`44-final-analysis.log`). Named-file format verification and the full diff
whitespace checks are listed in `commands.json`. The manifest also declares the
final committed-HEAD whitespace check; that post-commit result lives in the
external command ledger and final handoff so the manifest need not refer to its
own commit hash. No Dart source changed between the full runs and this commit.
