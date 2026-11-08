---
id: boo-rabw
status: open
deps: [boo-vtvp]
links: []
created: 2026-11-08T14:38:45Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Alert the user when two devices saved different places in a book

Today a position conflict from personal-record sync shows only on Settings > Personal records (lib/sync/screen.dart). The Settings row always reads 'Bookmarks, history, and progress', and a background sync shows the conflict list with no message, so the user does not learn that a choice waits. Add a visible, non-blocking notice where the user will see it (for example on the book, the player, or the Settings row) that leads to the choice. Found while preparing landing-page screenshots on 2026-11-08.

## Acceptance Criteria

A conflict found by a background sync produces a visible notice outside the Personal records page; the notice leads to the choice; it disappears after the choice; no notice appears without a conflict; tests cover each case.


## Notes

**2026-11-08T15:34:25Z**

Alert designs are in docs/mockups/personal-records-a.html (notice on the book page above Resume and a pill in the player, both open the choice in a glass sheet) and docs/mockups/personal-records-b.html (one glass pill above the mini player on every tab, hidden by its x until a new conflict). Both read RecordSync.conflictsNotifier and add a Settings tab badge and a Settings row line. Awaiting the user's choice on boo-vtvp.

**2026-11-08T15:41:45Z**

Design chosen by the user on 2026-11-08, a hybrid of docs/mockups/personal-records-a.html and personal-records-b.html. From design A: the conflict alert appears on the conflicting book only, as a glass notice above Resume on the book page and a pill under the chapter in the player; Choose opens the choice in a cover-tinted glass sheet right there (the same choice component as the page). From design B: each conflict draws both places as pins A and B on one track of the whole book, then two columns with Keep buttons (for bookmark-edit and edit-against-delete conflicts, which have no place on a track, show only the two columns); the page opens with a one-line status strip and a round Sync button, problems stack as banners under it, and with several conflicts one is open and the rest are collapsed rows. Shared by both: the Settings tab badge with the count of waiting choices, the Settings row line in copper ('A choice waits · First Frost'), the boo-cows labels, the note that both places stay as bookmarks, and one source of truth (RecordSync.conflictsNotifier). The sync coordinator must report the cause of a failure (no connection versus plugin missing) instead of one combined message.
