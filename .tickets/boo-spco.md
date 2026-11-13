---
id: boo-spco
status: in_progress
deps: []
links: []
created: 2026-11-08T03:16:28Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# A playback error from one book stays as a banner on every tab after another book plays

Found on the Pixel 8 on Nov 7 (build 1abdb6b). Tapping Listen on a book that is not downloaded (The Lesser Devil) sets the Playback message 'Download every file in this audio edition before listening.' Afterwards, Blood Music (fully downloaded) played normally, but the message stayed: at the top of the Downloads tab, on the Blood Music book page, in the History sheet and in the player. In the player it also runs to the card's left edge with no horizontal padding. A message must belong to the action and the book that caused it: clear it when another book or edition opens or starts playing, and show it only next to the book that it is about. Fix the player padding.

## Implementation scope — 2026-11-13

The behavior above is settled. Reproduce the remaining defect against current
code before changing it: a successful new `_open` already clears the message,
while `_play` of an already open edition does not. The historical report alone
does not establish which current path still fails.

Playback owns the notice and its lifetime. Keep one coherent representation
for book/action notices and storage-recovery notices. Consumers receive the
information they need without duplicating ownership or comparing message text.
An error about another book must not appear in the current player's content,
an unrelated book page, or unrelated tab content. Genuine current errors and
record-read/save recovery notices remain visible in their appropriate scope.
Successful open/play clears obsolete action errors. Account replacement and
late results must not attach an old notice to a new account or edition.

Preserve the approved styling, glass surfaces, narrow subscriptions and
controller ownership. Correct the player message padding using existing
spacing. Audit every consumer of Playback messages, including History and
gallery fixtures. Add behavioral regressions through actual owner operations
and widget consumers, including recovery-notice preservation. Keep the
separate Ask-at-Play work in boo-56h7 untouched.

Required evidence: meaningful original failures, passing focused and affected
playback/catalog/app/sync tests, the full suite, affected analysis, formatting,
complete-diff whitespace checks, and one fresh read-only review with separate
correctness, fulfillment and design verdicts. Retain all failures and skips.
Use Nix and Flutter concurrency two; one heavy command per owner. Coverage and
mutation testing stay with the parent after acceptance. Android inspection is
blocked by t1-dth0; do not retry device/browser tools for this ticket. Host
widget tests are not device acceptance. Parent owns integration and closure.

## Delegation — 2026-11-13

Original base: `c603591b313afbd8e167e83fd5e14e2e13978fad`.
Lead: codex/gpt-6-astra, xhigh. One fresh read-only reviewer: same model, high.
`clientRequestId`: `bookfin-boo-spco-astra-20261113-1`.
`taskId`: `node:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-boo-spco-astra-20261113-1`.
`childThreadId`: `thread:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-boo-spco-astra-20261113-1`.
Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-boo-spco-astra-20261113-1>

The lead builds and fixes in its T3-owned worktree. Parent owns integration,
device acceptance, hardening and closure. No additional product question is
open. Concurrent Ask-at-Play work remains separate.

## Implementation evidence — 2026-11-13

The ticket lead started clean at `c603591b313afbd8e167e83fd5e14e2e13978fad`
in `/Users/alexispurslane/.t3/worktrees/bookfin/t3-369cacef`, branch
`t3/369cacef`. The original-base diff was empty. The integrated `tf-il7u`
and `t5-rplx` test corrections remain unchanged.

Fresh tests reproduced the already-open Play path, unrelated tab/book/player/
History visibility, recovery loss on open, an old-account read failure after
sign-out, and player text reaching the left edge. The valid original-code run
had eight behavioral failures and one pass. A missing test-fixture field and
an interrupted widget test run are retained separately and are not red proof.

Playback now owns an edition/action notice and a separate record-recovery
notice. Save failure is derived from the existing failed-account write state.
The status supplies one scoped message query; the old unscoped message getter
is removed. The shared notice controller uses the narrow status signal and
serves tabs, book pages, player and History. Tabs and History show account
record notices, a book page selects that book's editions, and the player selects
its open edition. Successful open or Play clears action errors without losing
recovery or pending-save warnings. Retry saving resolves only the failed-save
state. Player notices use the stage's existing horizontal inset of 24 logical pixels and
empty notices consume no padding.

Command failures keep the edition that the command attempted before waiting.
Late account-read failures and failure-handler pauses cannot write a notice to
a replacement account. A failed load of an obsolete source cannot describe its
replacement. Automatic reopening uses the same audio-failure handling instead
of calling a decoder error a record-recovery error. Replacement offers, stored
positions, history, Undo, error-vs-exception behavior and narrow signals remain
covered by the affected suites. New widget tests exercise Listen, Play, History
and Retry saving through their real controllers.

Checks and full retained logs are indexed in
`docs/evidence/boo-spco-verification.json`. The first affected run exposed two
sync test files still using the removed getter; their assertions were migrated
without changing behavior. The corrected affected run passed 1,484 tests with
three optional skips. Static analysis passed. Full-suite and review results
are recorded in the evidence manifest and subsequent notes.

Integration considerations: concurrent `boo-56h7` also changes Playback and its
Play command. Preserve its Ask-at-Play decision while adapting its command
wrappers to `PlaybackOperation` and the scoped status representation. No work
from that ticket was implemented or imported here. Review the combined Play
success transition and rerun the affected playback/sync/widget suites.

This is host-test evidence, not Android visual acceptance. The existing
`t1-dth0` device blocker was not retried or bypassed. No browser, device,
credentials, coverage, general mutation campaign, timing-threshold changes,
push, PR, merge or ticket closure was performed. Parent owns integration,
acceptance, hardening and closure.

The first full run passed 3,712 tests with 27 optional skips and failed two
gallery tests. The migrated fixture now shows the real save-error message,
putting player controls beyond the list's initially built children. Those two
tests now use the gallery's existing scroll-to-control helper before acting;
the Play, jump and Undo assertions are unchanged. No timing limit changed.
The notice tests also await explicit entry into a held read instead of assuming
an event-queue drain reached it. The final focused run passed 43 tests across
notices and gallery, and analysis of all `lib` and `test` passed.

The final full run passed 3,714 tests with 27 optional skips. Changed-Dart
format verification passed for 22 files. The targeted layout scan reported
no findings; it does not establish device acceptance. All source and test
changes are ready for the single fresh read-only review. The ticket remains
in progress until the parent integrates and closes it.

Implementation commit: `3903711325358a4b95a9b28d9f0e19d475b74323`.
The worktree reflog records a branch rename at the original base from
`t3/369cacef` to `t3/playback-notice-ownership`; the lead issued no switch,
reset or rename command. The path and base history are unchanged. The current
branch is `t3/playback-notice-ownership`. The committed original-base whitespace
check passed and the implementation checkout was clean.

## Single review and fixes — 2026-11-13

The authorized `codex/gpt-6-astra` reviewer completed at high reasoning effort.
Its original report is preserved unchanged in
`docs/evidence/boo-spco-review-original.json`. Correctness, fulfillment and
design each required changes. There is no second review.

- F1: failed Resume and History actions had no visible explanation. Resume
  now shows the Playback-owned notice with the attempted book. A failed audio
  restore keeps History open and shows the notice with the attempted entry;
  successful retry closes History and shows the destination. The entry id is
  part of the notice scope. Account record notices remain in History's header.
- F2: a delayed restore and an already-published error could describe a new
  source under the same edition id. Playback now retains the original account
  generation and source with its notice. One source-validity rule governs
  publication, library reconciliation and the on-demand invariant check.
- F3: rejecting an obsolete error skipped playback cleanup after pausing the
  decoder. Cleanup now proceeds for the current account even when that notice
  is suppressed. The retained edition can be played again normally.

`review-red` reproduced all three findings: 22 tests passed and eight behavior
tests failed. The failures cover both History actions and bookmarks, with a
retained player and with nothing open, delayed/source-replacement notices, and
an obsolete failed load while another edition was playing. The first green
attempt exposed a test wait mistake: `flush` waits for writes, not the audio
command. The tests now await a following queued command before checking the UI.

Follow-up tests also reproduced Play being labelled Open when reloading, and
the Resume error being excluded from screen-reader semantics. Play retains
its initiating operation through reload. The notice is outside the Resume
button's replaced semantics. A corrected visibility/handle-lifetime test was
rerun against the old layout and failed meaningfully (`review-red-accessibility`).
All intermediate failures and fixture corrections remain in the manifest.

The final focused review-fix run passed 130 tests with no skips. Broader final
results, exact commands, log hashes, review link and finding resolutions are
recorded in `docs/evidence/boo-spco-verification.json`. Review gaps about missing
host regressions are covered by these new tests; Android acceptance remains
excluded under t1-dth0. Parent still owns integration, hardening and closure.

Final review-fix validation: 1,581 affected tests passed with three optional
skips; the full suite passed 3,724 with 27 optional skips. Analysis of all
`lib` and `test` reports no issues, and format verification reports 24 files
with zero changes. A first analysis run reported one info-level missing-braces
lint despite exit 0; the braces-only correction is retained and final analysis
and formatting passed afterward. No behavior changed after the full run. The
final layout source scan has no findings. These checks do not establish device
acceptance. Both prerequisite correction files remain unchanged.

## Parent integration — 2026-11-13

Integrated the reviewed implementation and fixes while retaining boo-56h7's
Ask-at-Play, external Play preservation, marker reconciliation and stale-seek
restoration. Commands now carry the attempted operation in both external Play
and choice acceptance. Successful Play clears the action error and still
publishes any requested choice.

Combined inspection found that restart with a durable listening choice skipped
the automatic reopen error handler. Two regressions, on preferences and SQLite,
failed with an account-wide record-recovery error after a decoder load failure.
The existing automatic-reopen handler now owns both reopen paths. Both tests
pass and confirm unchanged saved History/choice plus successful recovery of the
local and remote places. No second review stage was started. Parent evidence is
being collected under docs/evidence/boo-spco/integration; broad checks pending.
