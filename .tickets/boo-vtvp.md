---
id: boo-vtvp
status: open
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

