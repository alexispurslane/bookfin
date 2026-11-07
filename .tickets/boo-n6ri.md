---
id: boo-n6ri
status: in_progress
deps: []
links: []
created: 2026-11-07T16:47:37Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Rebuild Downloads on the library row with totals, network state, and per-row controls


## Notes

**2026-11-07T16:47:37Z**

BookRow (library_view) gained detail/below/trailing slots; DownloadsPage uses it with remove/cancel/retry icon buttons outside the row tap, a summary card with total size, audiobook/ebook counts and network state, and opens book details on tap. Retained storage view keyed so its scan survives list changes.
