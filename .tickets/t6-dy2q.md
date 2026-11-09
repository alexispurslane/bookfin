---
id: t6-dy2q
status: open
deps: []
links: []
created: 2026-11-09T15:40:31Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Draw list markers that a book places inside (list-style-position: inside)

Found during boo-8ucr. prepare.dart _start drops a list item's marker when its style has list-style-position: inside, so such a list shows no numbers or bullets on the page. CSS draws an inside marker as an inline box at the start of the first line, after the text-indent. A small fix: put the marker before the first word as a label that no node owns, as PreparedSection.excerpt now does for a note's number (a RaisedRun with node -1). This changes the page layout of books that use inside markers, so run the fidelity test and the corpus check before and after.

