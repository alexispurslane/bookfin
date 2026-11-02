---
id: boo-3oq0
status: open
deps: [boo-p58t, boo-6h8w, boo-9wgg, tb-5fyd, tb-887c]
links: []
created: 2026-11-01T21:37:34Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Sync Bookfin records through validated Jellyfin storage

Implement the transport selected by the feasibility ticket. Prefer existing Jellyfin storage; build the small plugin only if that is the recorded outcome. Keep record ownership and conflict rules in Bookfin.

## Design

docs/plans/bookfin.md

## Acceptance Criteria

Two devices merge offline bookmarks and history, retain deletions, tolerate duplicate retries and clock differences, and preserve both positions on true resume conflicts. Test against actual Jellyfin.

