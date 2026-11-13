---
id: boo-56h7
status: in_progress
deps: []
links: []
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
