---
id: boo-dez0
status: in_progress
deps: [tb-887c, tb-5fyd]
links: []
created: 2026-11-02T12:05:50Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Prove dedicated Jellyfin storage for retained Bookfin records

User selected a server storage surface separate from ordinary playlists, with history retained until explicit deletion. Prove a small Jellyfin plugin in a disposable fixture; no production installation. Existing research remains input, not proof that the plugin works.

## Design

docs/plans/bookfin.md

## Acceptance Criteria

Authenticated account isolation; durable concurrent independent operations; retry deduplication; discovery; explicit deletion without delayed resurrection; no automatic history or device expiry; preserve offline pending actions; restart proof; documented limits. Keep merge/conflict semantics owned by Bookfin.

