---
id: td-6hd7
status: closed
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


## Review correction and resolution

The single fresh Astra review of boo-7z9a accepted the exact-byte preservation tests but found an uncovered reporting path (R4): damaged retained preferences discovered after active restore could remain unreported until restart. Therefore the earlier pre-review statement that the full retain-and-report requirement was proved was premature. The reviewer marked fulfillment `changes-required`, not passed.

The lead reproduced R4 as a meaningful red in `/tmp/boo-7z9a-review-red.log`, then fixed notice reconciliation at the catalog ownership boundary. The controller reads only the small choice record through its account write queue; the after-first-frame migration completion and unchanged server response adoption both use that boundary. The tests verify exact retained text, active reporting without restart (with and without a server refresh), unchanged library identity and no server-cache write. The four reviewed behavior regressions passed together in `/tmp/boo-7z9a-review-green.log`. The complete verification results for the final fix follow in boo-7z9a.

No second review, Android test, operating-system process kill, coverage, mutation testing, integration or closure was performed by this lead.


Final fix verification completed: 528 affected tests passed; the complete suite passed 3,322 tests with 26 existing skips and no failures (`/tmp/boo-7z9a-review-affected-final.log`, `/tmp/boo-7z9a-review-full.log`). All review findings were resolved in one fix stage. td-6hd7 is fully proved within the requested automated real-file retain-and-report scope, including R4's active notice path. The ticket remains open only for parent integration, acceptance/hardening and closure; no further implementation gap is known.

## Parent integration and closure, 2026-11-13

Integrated with boo-7z9a as 7c4fa38f and c475c4f3b229dfb115a76ab578b7e0ccc90081b1. The parent inspected exact-byte preservation, failed-retention ordering, fresh reopen, and active recovery-notice evidence, including the R4 red-green regression. Production/tests match the child's final commit. The combined main suite passed 3,353 tests with 27 existing skips and no failures (`/tmp/boo-7z9a-integrated-full.log`); affected analysis, 14-file formatting and catalog browser compilation passed. Full commands and limits are recorded in boo-7z9a.

The requested retain-and-report implementation is merged and verified, so this ticket closes with boo-7z9a. Device acceptance and post-acceptance hardening remain project-level work; no actual process-kill or Android proof is claimed.
