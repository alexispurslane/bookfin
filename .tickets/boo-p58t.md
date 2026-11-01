---
id: boo-p58t
status: open
deps: [boo-gxm8]
links: []
created: 2026-11-01T21:37:34Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Prove Jellyfin catalog media and extra-record storage

Inspect the actual Jellyfin version and representative book libraries. Test ordinary-user access, chapters, downloads, per-item progress, ebook discovery, and custom display preferences in a disposable namespace.

## Design

docs/plans/bookfin.md

## Acceptance Criteria

Record a decision for existing storage versus plugin. Prove concurrent writes, discovery, deletions, isolation, retry, size limits, and restart behavior. Do not promise full sync from a successful single-device round trip.

