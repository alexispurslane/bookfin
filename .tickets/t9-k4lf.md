---
id: t9-k4lf
status: open
deps: [boo-7o92]
links: []
created: 2026-11-02T04:06:10Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Manage retained downloads outside the selected catalog

Downloaded files remain account-private when an item is removed from Jellyfin or its library is deselected. Current catalog screens intentionally hide these sources and never silently evict them. Provide an explicit account-scoped storage view that can remove retained files no longer reachable from the active catalog, without deleting unrelated files or another account files.

## Design

docs/plans/bookfin.md; docs/downloads.md

## Acceptance Criteria

Show retained storage separately from current edition availability. Tests prove account isolation, safe explicit removal, unreadable metadata handling, and no silent eviction.
