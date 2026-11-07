---
id: boo-eg9h
status: in_progress
deps: []
links: []
created: 2026-11-07T15:30:28Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Show Jellyfin covers, series, and book metadata with an offline cover cache


## Notes

**2026-11-07T15:35:06Z**

Book now carries cover (CoverRef itemId+tag), description (HTML stripped), genres, publisher, year. Series comes from Jellyfin SeriesName on Book and AudioBook items (not plain Audio); series order from IndexNumber on Book items only; a details correction wins. This revises the earlier plan caution about TV series fields because the user asked for automatic grouping. DiskCovers keeps one file per item and tag under filesDir/bookfin-covers/<account hash>/ and works offline.
