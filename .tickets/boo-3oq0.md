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

**2026-11-02T23:59:04Z**

Independent static review of ccff7dc/e9721ff requires correction before integration: F1 rejected refresh advances store observation and can delete discovered bookmarks; F2 active-player flush invalidates or overwrites conflict choices; F3 malformed local sync metadata escapes storage recovery; F4 conflict choices lack readable book/edition/position identity. Continuous builder steered to preserve current PDF milestone then fix shared snapshot acceptance and persistence semantics with meaningful race regressions. No sync integration or acceptance claimed. Android listening lane remains independent. Growth t6-t9po and plugin deployment t6-il6y stay open.
