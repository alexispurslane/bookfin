---
id: t6-0cjf
status: open
deps: []
links: []
created: 2026-11-08T16:46:14Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Next chapter can stay on the same page when a chapter starts in the middle of a page

The dock's Next chapter arrow (boo-bz3x) goes to the first chapter that starts after the visible place, which is the start of the shown page. When a chapter starts in the middle of the shown page, as in an EPUB section with several contents entries, that chapter's page is the shown page, so a tap does not move and the arrow seems stuck. The showcase books start each chapter in its own file, so it does not show there. A fix needs the end of the visible page as a text progress, which the epub engine reports for previews (PagePicture.end) but not for the visible location.

