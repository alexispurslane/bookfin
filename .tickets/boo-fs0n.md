---
id: boo-fs0n
status: open
deps: []
links: []
created: 2026-11-01T21:37:34Z
type: epic
priority: 1
assignee: Alexis Purslane
---
# Bookfin Android audiobook and ebook companion

Android-first Flutter client for Jellyfin. Local listening, book and series organization, readers, seek recovery, and sync. Start with Jellyfin-only extra-record storage; a plugin is an accepted fallback.

## Design

docs/plans/bookfin.md

## Acceptance Criteria

User can download and listen offline, read accompanying ebooks, recover accidental navigation, and sync supported records. Shared T3 Device testing works from desktop and phone.


## Notes

**2026-11-01T22:02:10Z**

User approved the original mockup feature structure. Preserve it nearly exactly. Revise the appearance to cream/sepia, high-quality serif text, geometric headings, airy rounded surfaces, smooth transitions, and automatic sunset night colors. Visual implementation: boo-61vt.

**2026-11-03T20:26:04Z**

User requested a UI coherency and simplification pass after all acceptance tests finish, with no feature loss. Tracked as boo-4ixi; current acceptance continues unchanged. Later pass may revisit presentation/layout while preserving cream/sepia identity and established capabilities; genuine interaction tradeoffs require concrete alternatives.
