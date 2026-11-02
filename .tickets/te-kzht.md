---
id: te-kzht
status: in_progress
deps: []
links: []
created: 2026-11-01T23:32:51Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Implement offline production city selection

The approved plan authorizes selected-city input. No new user decision is required. Implement a useful searchable offline city selection with documented dataset provenance and coverage through the existing appearance controller. Approximate foreground location can remain a later enhancement; do not request precise/background location or use remote lookup. This ticket completes original boo-61vt acceptance and gates it.

## Acceptance Criteria

Production users can search, select and remove a city. Selected coordinates persist through the existing controller and drive local sunrise/sunset appearance. Removal restores explicit system fallback; manual overrides remain. Validate input, distinguish same-name cities, document dataset coverage/license and test selection, persistence and Android interaction. Correct obsolete approval-gate claims in UI/docs.
