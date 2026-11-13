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
