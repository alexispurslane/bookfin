---
id: boo-3oq0
status: in_progress
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


## Notes

**2026-11-02T22:49:09Z**

User explicitly requests a continuous builder lane: production record sync, then remaining ebook formats and approved OCR, while separate acceptance agent owns Android. Begin implementation against reviewed dedicated-plugin storage and existing record owners; outstanding prerequisite acceptance gates remain open and must be respected before closure. No claim that dependencies are fully accepted.
