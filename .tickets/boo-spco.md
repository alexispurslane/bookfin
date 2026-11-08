---
id: boo-spco
status: open
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

