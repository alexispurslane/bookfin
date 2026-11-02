---
id: tb-5fyd
status: open
deps: []
links: [tb-887c, t3-7fv1]
created: 2026-11-02T02:39:05Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Decide history retention and long-offline replica recovery

Storage-independent product decision found during t3-7fv1. Define the retained listening-history interval or count, paired-device membership limits, and whether a device may remain offline indefinitely while preserving automatic upload of every pending action. A replica is one app installation with durable operation numbering. Retention must bound protocol overhead without forgetting deletion protection. Neither private playlists nor a small plugin removes this decision.

## Design

docs/plans/bookfin.md; docs/research/jellyfin-playlist-protocol.md

## Acceptance Criteria

User chooses and records exact retention and replica-admission rules, including whether retirement is timed or explicit, treatment of pending actions on a retired device, and whether delete-versus-concurrent-edit is retained as a conflict. No expiry duration or silent loss is invented by implementation.
