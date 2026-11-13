---
id: boo-56h7
status: open
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
