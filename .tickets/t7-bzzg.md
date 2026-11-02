---
id: t7-bzzg
status: open
deps: []
links: [boo-2cgp]
created: 2026-11-02T06:04:42Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Resolve real Jellyfin interrupted-download range resume acceptance

boo-2cgp real production LocalDownloads acceptance against the pinned disposable Jellyfin 12.4.0 observes /Items/{id}/Download returning Last-Modified and Accept-Ranges but no HTTP ETag. The existing documented safety model requires a strong HTTP ETag for saved-prefix reuse. It therefore discards the saved prefix and retries the exact original bytes with HTTP 200. Do not relax that identity guard without an approved safe model. Synthetic transfer tests prove strict Range/If-Range handling, not real Jellyfin prefix reuse.

## Design

docs/plans/bookfin.md; docs/downloads.md; docs/acceptance/jellyfin-app.md

## Acceptance Criteria

Resolve whether safe full-restart recovery meets the approved user requirement, or implement and prove safe real-Jellyfin prefix reuse under a settled model. Exercise real app downloads, replacement safety, process interruption, account/source identity and exact completed bytes. Do not claim a synthetic server response as Jellyfin resume proof.
