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
