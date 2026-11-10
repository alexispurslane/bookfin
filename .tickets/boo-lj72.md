---
id: boo-lj72
status: in_progress
deps: [tb-9mcf]
links: []
created: 2026-11-10T21:56:07Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Remember each book’s PDF view and margin trimming

User changed the product decision on 2026-11-10: remember each book’s last Original/Page words/Text choice and Trim margins on/off across app restarts. Supersedes session-only view in tb-9mcf and account-wide trim behavior. Use account-scoped book identity, one saved preference owner and existing durable reading settings storage. Restore before first useful reader view; preserve legacy settings sensibly and never lose positions, history or bookmarks. Keep font size behavior unchanged. Include restart, book/account isolation, failed-save/retry, legacy migration and UI restoration behavior evidence. Update the plan to the new settled decision.

## Acceptance Criteria

Reopening each of two books after restart restores its own exact PDF view and trim choice. Switching accounts cannot leak preferences. Changes persist through the real reading store without rewriting or losing reading records. Required checks and one fresh review with resolved findings.


## Notes

**2026-11-10T22:22:07Z**

Build stage complete in t3/remember-pdf-view-settings from c9200c085612a0978dd56d4fa1ac943c1f92a67d. ReaderSession now owns per-account Book.id PDF choices in existing reading settings and derives the current choices without duplicate session fields. Legacy global trim remains only the untouched-book fallback. No font-size or record model changes. Both real LocalResumeStore transports were traced; arbitrary settings metadata already survives, so no storage changes were needed. Meaningful red: session-red.log shows book/account leakage, failed restart and first-frame restoration, ignored malformed preferences; an unrelated empty-record test fixture was corrected. store-red.log shows seven intended failures across preferences and actual SQLite reopen/retry. Green: 78 focused tests passed in focused-final.log, including both storage backends, all three exact views, book/edition/account isolation, legacy SQLite migration, malformed durable settings, failed SQLite save/retry and retained reader behavior. Logs: /tmp/bookfin-boo-lj72. Required format/analyze/full suite and one fresh read-only review remain. Existing preferences-only invariant-check limitation recorded separately as tc-eri9; SQLite invariant checks pass. No devices, coverage, mutations, native changes, push, merge, PR or closure.
