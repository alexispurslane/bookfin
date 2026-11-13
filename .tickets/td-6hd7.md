---
id: td-6hd7
status: open
deps: [boo-7z9a]
links: [boo-7z9a]
created: 2026-11-09T15:41:19Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Keep an unreadable saved catalog aside instead of replacing it at the next refresh

Found during boo-j1lm. When the saved catalog of an account cannot be decoded, restore() and the sign-in say so, but the launch refresh in lib/main.dart (restore().then(refresh)) and any later refresh write a fresh catalog over it, which drops the account's corrections. The engine rules say: if a store cannot be read, keep the file aside and report it, and do not replace it with an empty store. boo-j1lm made sign-in skip its automatic catalog read in this case, but the launch refresh still replaces the file. Move the unreadable text aside (for example under a .unreadable key) before the first write, and report it.


## Coordination with boo-7z9a

The parent assigned the correction-store lead the linked unreadable-legacy preservation behavior. Retain unreadable bytes before allowing replacement and keep the existing error report. The parent closes this ticket only after real-file regression evidence and integration. No separate writer is active for this bug.
