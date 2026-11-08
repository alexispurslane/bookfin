---
id: boo-vtvp
status: in_progress
deps: [boo-cows]
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

**2026-11-08T15:41:45Z**

Design chosen by the user on 2026-11-08, a hybrid of docs/mockups/personal-records-a.html and personal-records-b.html. From design A: the conflict alert appears on the conflicting book only, as a glass notice above Resume on the book page and a pill under the chapter in the player; Choose opens the choice in a cover-tinted glass sheet right there (the same choice component as the page). From design B: each conflict draws both places as pins A and B on one track of the whole book, then two columns with Keep buttons (for bookmark-edit and edit-against-delete conflicts, which have no place on a track, show only the two columns); the page opens with a one-line status strip and a round Sync button, problems stack as banners under it, and with several conflicts one is open and the rest are collapsed rows. Shared by both: the Settings tab badge with the count of waiting choices, the Settings row line in copper ('A choice waits · First Frost'), the boo-cows labels, the note that both places stay as bookmarks, and one source of truth (RecordSync.conflictsNotifier). The sync coordinator must report the cause of a failure (no connection versus plugin missing) instead of one combined message.
