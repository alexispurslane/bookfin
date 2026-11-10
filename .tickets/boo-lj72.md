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

