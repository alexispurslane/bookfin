---
id: tf-1rv4
status: open
deps: []
links: []
created: 2026-11-09T02:13:04Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Paste a line break into the reader's search field as a space

Found in tc-iwqp. Copied text from two paragraphs holds a line break between them. The search field is one line, and Flutter drops the line break on paste, so 'her to.' and 'Every' join as 'her to.Every', which no page of the book holds. Search already matches white space as one space, so the field can turn each line break into a space. Seen on Android 16 in the evidence of docs/evidence/reader/native/selection/04-pasted-into-search.png.

## Acceptance Criteria

Pasting text with a line break into the search field gives a space in its place, and the search finds the passage.

