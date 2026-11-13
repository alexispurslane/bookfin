---
id: td-6hd7
status: in_progress
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

## Linked implementation evidence, 2026-11-13

boo-7z9a now retains unreadable native catalog bytes before any replacement it prepares. The regressions exercise malformed legacy JSON, invalid UTF-8, and structurally valid legacy text whose entries cannot build books. After a successful refresh, browsing resumes, the exact old bytes remain in a separate file, and the account retains a recovery notice across reopening. Readable legacy choices are extracted even when the server entries cannot build. A preservation failure prevents replacement and can retry. Tests use real files and controlled failures, not a process kill.

Integration, review resolution, final verification and ticket closure remain with the assigned lead and parent as described in boo-7z9a. No separate writer or closure was started.

Final implementation verification: 52 focused real-file storage/choice tests passed (`/tmp/boo-7z9a-green-io-guard.log`), 522 affected tests passed (`/tmp/boo-7z9a-affected-final.log`), and the full suite passed 3,316 tests with 26 existing skips and no failures (`/tmp/boo-7z9a-full-final.log`). The regression is fully proved for the assigned automated scope; the single fresh review and parent integration/closure remain pending. No Android or actual process-kill proof is claimed.
