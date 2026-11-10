---
id: t6-1luw
status: open
deps: []
links: [tb-22fu]
created: 2026-11-08T16:46:14Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# The PDF scrub bar announces the next page at the end of the shown page

Seen with boo-bz3x on the bookfin-bz3x emulator with Windfall (showcase fixture). On source page 1 of 3, TalkBack reads the bar's value as 'Page 2 of 3', while the label says 'Source page 1 · Page 1 of 3'. Cause: a PDF place sits at the end of its page (BookMap.fractionOf counts the shown page as read), and the bar's describe callback names the place at that fraction with BookMap.targetAt, which is the start of the next page. The old ReaderScrubBar did the same before boo-bz3x. Expected: the bar's spoken value names the shown page while no drag runs.

