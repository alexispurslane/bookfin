---
id: boo-27e6
status: in_progress
deps: []
links: []
created: 2026-11-07T16:13:08Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Read book series from Jellyfin collections and (Series #N) titles


## Notes

**2026-11-07T16:17:19Z**

Real server survey (via one-time sign-in): 0/1478 audiobooks have SeriesName; 518 are in exactly one book collection (BoxSet); 495 titles end in "(Series #N)". Catalog now fetches BoxSet membership in batches of 8 and stores it as BookfinCollections on each entry; unreadable collections never fail the catalog. Result on the real library: 1007 shelf entries, 134 series cards, The Wheel of Time 1-14 in order, catalog in 5 s.
