---
id: boo-56h7
status: closed
deps: []
links: [boo-hxmd]
created: 2026-11-12T23:41:00Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Ask which place to play when a sync brought a newer place to a paused open edition

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. `refreshPersonalRecords` (lib/playback/playback.dart:597-638) replaces `_resumes` after a sync but leaves `_position` unchanged. `_play` (1404-1424) then plays from the old position, and `_save` (1681-1702) replaces the newer resume from the other device with no conflict and no Undo. Listen on the book page goes through `_open` and applies the newer place, so the result depends on the button. docs/plans/reading-history.md:194 says that a sync never moves an open book. The audio service keeps an edition open for days, so the user must decide whether that rule still holds for a paused edition. Proposed model: a newer place from another device moves the paused decoder as an `open` move with Undo, through the path that `_open` uses.


## Notes

**2026-11-13T01:09:37Z**

User decision, 2026-11-12: Ask at Play. The paused edition stays at its place after a sync, so the rule in docs/plans/reading-history.md:194 holds. When the user taps Play and a newer place from another device exists, a glass choice (showGlassChoices) offers the place of this phone or the newer place. Play must never replace the newer resume silently. Open point that the user did not decide: Play from the notification, a headset or the lock screen cannot show a choice. Proposed default by the orchestrator: play from the place of this phone, keep the newer place as its own History entry so that both moves stay, and show the choice when the app next comes to the front. Confirm this default with the user before the build.

## Pending product choice, 2026-11-13

The parent has asked what headset and lock-screen Play should do when a newer remote place exists: play from this phone's place while preserving both places in History and defer the question to the foreground, or remain paused until an in-app choice. No reply has arrived yet. Do not infer a choice from elapsed time or launch dependent implementation. Independent download-restoration work can proceed.

## Settled behavior and implementation scope — 2026-11-13

The user chose: headset, notification and lock-screen Play start from this
phone's place. Keep both this phone's place and the newer place from another
device in History. Ask which place to use when the app comes to the foreground.
In-app Play asks before playback starts. A sync alone never moves the open
edition. This supersedes the pending-choice notes above.

Playback owns the pending place choice and its record changes. Screen
controllers show the shared glass choice and report the answer. Preserve
durable records before a resume save can replace the newer place. Reuse
existing move, History, Undo, account and source-identity rules. Do not add a
parallel writer or change the sync refresh/audio-command separation.

Cover both choice outcomes, cancellation, external Play followed by foreground,
repeated Play and refresh, a choice made stale by a newer sync, edition/account
replacement, failed writes, restart recovery and the actual UI/audio-service
callers. Prove meaningful red behavior before implementation. Run focused,
affected and full suites through Nix at concurrency at most two, plus analysis,
formatting and complete-diff whitespace checks. Preserve failure and skip logs.
The ticket lead builds and fixes. Exactly one fresh read-only reviewer assesses
correctness, fulfillment and design. Parent owns integration, user acceptance,
coverage, mutations and closure. Device work remains blocked by t1-dth0.

## Parent launch record — 2026-11-13

- Original base: `62f4fb238861fd601acb2668a9a4d646c8a28c77`.
- Task ID: `node:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-boo-56h7-astra-20261113-1`.
- Child thread ID: `thread:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-boo-56h7-astra-20261113-1`.
- Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-boo-56h7-astra-20261113-1>.
- Client request ID: `bookfin-boo-56h7-astra-20261113-1`.
- Branch at launch inspection: `t3/preserve-external-play`.
- Worktree: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-fd6f0347`.
- Lead: codex/gpt-6-astra, xhigh. One fresh read-only reviewer: the same model, high.
- Stages: build, review, then one fix stage if needed. Parent handles integration and closure.
- Launch accepted and running. No implementation result or acceptance is claimed.

**2026-11-13T21:05:44Z**

Implementation completed in t3/preserve-external-play from original base 62f4fb238861fd601acb2668a9a4d646c8a28c77. Playback owns the pending Play choice and atomic preservation through existing History/record-store paths. CatalogHome presents the shared glass choice and follows foreground lifecycle; book-page, mini/full-player, reader-cover and media-service callbacks are covered. Original destructive behavior proved red on preferences and SQLite. Final affected suite: 1253 passed, 3 skipped. Full suite: 3745 passed, 27 skipped. Affected analysis and format checks pass. Complete command/failure/skip manifest and original red patch: docs/evidence/boo-56h7/. Complete logs: /tmp/bookfin-boo-56h7-evidence/. Exactly one authorized read-only review is next. Native acceptance remains parent-owned under t1-dth0; no coverage, mutations, merge, push or closure performed. t5-rplx remains unexplained; tf-il7u unchanged.

## Review fixes, 2026-11-13

The single authorized reviewer assessed correctness, fulfillment and design as
changes-required. Its unchanged report is in
`docs/evidence/boo-56h7/original-review.json`; its thread link and each finding's
resolution are in `review-resolutions.json` beside it. No second reviewer ran.

BOO-56H7-R1: reproduced obsolete commits when sync replaced or deleted a choice
during its seek. The move now validates that choice at decoder confirmation,
and restores the prior local decoder place before rejecting a stale answer.
History, Undo and the current resume remain unchanged by the rejected move.

BOO-56H7-R2: reproduced obsolete questions after restart. Refresh and restoration
now share one validity rule. Replacement or withdrawal saves the marker through
the existing writer without selecting a resume. Restart uses the last local
journal action for this phone's place and checks the current resume after the
decoder loads. Tests also cover a failed marker write, refresh completion before
persistence, and sync while restart loading is held. The command manifest keeps
all meaningful red runs, an explicitly corrected ordinary-open test expectation,
and one corrected test-path command failure.

The focused and retained command/refresh regression run passes 154 tests.
The affected suite passes 1,275 tests with 3 skips. The final full-suite and
static-check results are recorded in the evidence manifest and validation note.
Parent retains integration, acceptance, hardening and closure. Native acceptance
is still blocked on t1-dth0. t5-rplx remains unexplained; tf-il7u is untouched.

Final full verification: first run 3,766 passed, 27 skipped, and the existing
t5-rplx assertion failed once at unread_records_test.dart:97. The unchanged
five-test isolated retry passed. The unchanged full retry passed 3,767 tests
with 27 skips. No reader source, test wait or timing threshold was changed.
Both full logs and every failure are retained in the manifest. Final affected
analysis reports no issues. The ticket remains in progress for parent integration.

## Parent integration — 2026-11-13

Integrated as ddf1cd8f and ac63796a. The parent inspected the complete change,
the original review and both demonstrated fixes. Original changes-required
verdicts remain unchanged; R1 and R2 have accepted evidence-backed resolutions.
All eleven Dart files match the final child sources exactly. The parent
archived and verified 48 child logs/ledger artifacts, including failures.

Combined full suite at ac63796a: 3,768 passed, 27 existing skips, zero failures.
Both real browser entry points compile to JavaScript. Analysis reports no
issues; formatting checks eleven files with zero changes. Whitespace passes.
Exact commands, logs, hashes and commit mapping are in
`docs/evidence/boo-56h7/integration/integration.json`.

Implementation is integrated and closed. Native acceptance is explicitly
retained in linked boo-hxmd, blocked by t1-dth0; host callback and reconstructed
restart tests do not establish Android media controls or process-kill behavior.
General coverage, mutation testing and release hardening remain with the parent
after acceptance. No native acceptance or release completion is claimed.
