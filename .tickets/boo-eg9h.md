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

**2026-11-07T16:05:59Z**

User decision 2026-11-07: same-titled audiobook and ebook in the same Jellyfin series and with the same author join as one book automatically, only when exactly one audiobook item matches. Explicit bookLinks (link or separate) always win. Outside a series, confirmation is still required.
