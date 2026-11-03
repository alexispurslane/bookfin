---
id: t7-bzzg
status: in_progress
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

## Notes

**2026-11-03T00:53:19Z**

Fresh fc4531c normal app exercised two real-Jellyfin download process interruptions (PIDs29400->29905->30209). Observer recorded broken connections then automatic full HTTP200 requests without ETag/Range/If-Range. Incomplete prefixes57344 and90112bytes remained incomplete; final398040bytes SHA2564a9250e74b118ec8c565a5d7f91f120482f822e48af2d02399993ecd55dcf855 exactly matched source, then normal app played recovered local file. Initial shorter-throttle attempt completed too soon and is explicitly not interruption evidence. Strong-ETag guard unchanged. Product choice still required: safe whole-file restart acceptable, or separately approve/prove a safe saved-prefix model. Evidence docs/evidence/playback/android-authorized-retest.md. Own files/services/routes cleaned; parent owns closure.
