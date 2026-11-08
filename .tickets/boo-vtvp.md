---
id: boo-vtvp
status: in_progress
deps: []
links: []
created: 2026-11-08T14:56:46Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Redesign the Personal records page

Settings > Personal records (lib/sync/screen.dart) looks poor: an unstyled list of text rows, a status sentence under a serif heading, plain text buttons for conflict choices, and lots of empty space (see docs/screenshots/sync-conflict-choose.png). Redesign it in the app's visual language (docs/mockups/bookfin.html) so sync state, last sync, damaged records, and conflict choices read clearly. Related: boo-cows (labels), boo-rabw (alert). Requested by the user on 2026-11-08.

## Acceptance Criteria

The page follows the approved mockup's look; sync status, last sync time, errors, and each conflict with its choices are clear at a glance; the user approves the new design before it is built.


## Notes

**2026-11-08T15:34:25Z**

Two designs for user approval, 2026-11-08: docs/mockups/personal-records-a.html (status card, choice tiles, alert on the book page and player with a choice sheet) and docs/mockups/personal-records-b.html (status line, side-by-side compare on a book track, app-wide alert pill). Both share the Settings tab badge and Settings row line. Both error mockups split 'no connection' from 'plugin missing'; RecordSync reports one failure message today, so the build needs it to report the cause.
